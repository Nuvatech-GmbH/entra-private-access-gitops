using namespace Microsoft.PowerShell.Commands

$script:GSA_CustomApplicationTemplateId = '8adf8e6e-67b2-4cf2-a259-e3dc5476c621'
$script:GSA_GraphBaseUri = 'https://graph.microsoft.com/beta'

function Get-GSAApplicationConfigFiles {
    <#
    .SYNOPSIS
    Liefert produktive Application-YAMLs (ohne Beispiel-Dateien *.example.yaml).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationsPath
    )

    return @(
        Get-ChildItem -LiteralPath $ApplicationsPath -Filter '*.yaml' -File |
            Where-Object { $_.Name -notlike '.*' -and $_.Name -notlike '*.example.yaml' }
    )
}

function Assert-MgConnected {
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        throw 'Microsoft Graph ist nicht verbunden. Führen Sie zuerst Initialize-GSAGraphSession aus.'
    }
}

function Invoke-GSAGraphBetaRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$RelativeUri,
        [object]$Body,
        [hashtable]$Headers = @{}
    )

    Assert-MgConnected

    $params = @{
        Method      = $Method
        Uri         = $RelativeUri
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 30)
        $params['ContentType'] = 'application/json'
    }
    if ($Headers.Count -gt 0) {
        $params['Headers'] = $Headers
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null
    try {
        return Invoke-MgGraphRequest @params
    }
    catch {
        if ($_.Exception.Message -match '\b403\b|Forbidden|Authorization_RequestDenied') {
            throw "Microsoft Graph verweigerte die Operation ($Method $RelativeUri). Prüfen Sie Application permissions (Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All) und Admin Consent für die Pipeline-App."
        }
        throw
    }
}

function ConvertTo-GSAGraphApplicationType {
    param([Parameter(Mandatory)][string]$ApplicationType)
    switch ($ApplicationType) {
        'enterprise' { return 'nonwebapp' }
        'quickAccess' { return 'quickaccessapp' }
        default { throw "Unbekannter applicationType: $ApplicationType" }
    }
}

function Get-GSAConnectorGroupByName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$CorrelationId
    )

    $escaped = $Name.Replace("'", "''")
    $filter = "name eq '$escaped'"
    $encoded = [System.Uri]::EscapeDataString($filter)
    $uri = "https://graph.microsoft.com/beta/onPremisesPublishingProfiles/applicationProxy/connectorGroups?`$filter=$encoded"

    $resp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
    if (-not $resp.value -or $resp.value.Count -eq 0) {
        throw "Connector Group wurde nicht gefunden: '$Name'"
    }
    if ($resp.value.Count -gt 1) {
        Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message "Mehrdeutiger Connector-Group-Name '$Name'; es wird der erste Treffer verwendet." -Data @{ count = $resp.value.Count }
    }
    return $resp.value[0]
}

function Get-GSADefaultUserAppRoleId {
    param([Parameter(Mandatory)][string]$ServicePrincipalId)

    $uri = "https://graph.microsoft.com/beta/servicePrincipals/$ServicePrincipalId?`$select=id,appRoles"
    $sp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
    $role = $sp.appRoles | Where-Object { $_.displayName -eq 'User' -and $_.isEnabled -eq $true } | Select-Object -First 1
    if (-not $role) {
        throw "Konnte die Standard-AppRole 'User' am Service Principal $ServicePrincipalId nicht ermitteln."
    }
    return [guid]$role.id
}

function Resolve-GSAPrincipalId {
    param(
        [Parameter(Mandatory)][string]$PrincipalType,
        [Parameter(Mandatory)][string]$PrincipalName,
        [Parameter(Mandatory)][string]$CorrelationId
    )

    switch ($PrincipalType) {
        'User' {
            $enc = [System.Uri]::EscapeDataString($PrincipalName)
            $uri = "https://graph.microsoft.com/beta/users/$enc"
            $u = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
            return [guid]$u.id
        }
        'Group' {
            $escaped = $PrincipalName.Replace("'", "''")
            $filter = "displayName eq '$escaped'"
            $q = [System.Uri]::EscapeDataString($filter)
            $uri = "https://graph.microsoft.com/beta/groups?`$filter=$q&`$select=id,displayName"
            $g = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
            if (-not $g.value -or $g.value.Count -eq 0) { throw "Gruppe nicht gefunden: '$PrincipalName'" }
            if ($g.value.Count -gt 1) {
                Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message "Mehrdeutiger Gruppenname '$PrincipalName'; erster Treffer wird verwendet." -Data @{ matches = ($g.value | ForEach-Object displayName) }
            }
            return [guid]$g.value[0].id
        }
        default {
            throw "principalName wird für principalType=$PrincipalType nicht unterstützt."
        }
    }
}

function Get-GSAApplicationSegments {
    param([Parameter(Mandatory)][string]$ApplicationId)
    $uri = "https://graph.microsoft.com/beta/applications/$ApplicationId/onPremisesPublishing/segmentsConfiguration/microsoft.graph.ipSegmentConfiguration/applicationSegments"
    $resp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
    return @($resp.value)
}

function Get-GSAAppRoleAssignmentsForResource {
    param([Parameter(Mandatory)][string]$ServicePrincipalId)
    $uri = "https://graph.microsoft.com/beta/servicePrincipals/$ServicePrincipalId/appRoleAssignedTo"
    $resp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
    return @($resp.value)
}

function ConvertFrom-GSAYamlDocument {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
        throw "Das Modul 'powershell-yaml' ist nicht installiert. Installieren Sie es mit: Install-Module powershell-yaml -Scope CurrentUser"
    }
    Import-Module powershell-yaml -ErrorAction Stop | Out-Null
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    return ConvertFrom-Yaml -Yaml $raw
}

function Get-GSAApplicationByDisplayName {
    param([Parameter(Mandatory)][string]$DisplayName)
    $escaped = $DisplayName.Replace("'", "''")
    $filter = "displayName eq '$escaped'"
    $q = [System.Uri]::EscapeDataString($filter)
    $uri = "https://graph.microsoft.com/beta/applications?`$filter=$q&`$select=id,displayName,appId,onPremisesPublishing"
    $resp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
    return @($resp.value)
}

function Get-GSAApplicationById {
    param([Parameter(Mandatory)][string]$ApplicationId)
    $uri = "https://graph.microsoft.com/beta/applications/$ApplicationId"
    return Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
}

function New-GSASegmentPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Destination
    )
    return @{
        destinationHost = [string]$Destination.host
        destinationType = [string]$Destination.type
        port            = 0
        ports           = @($Destination.ports)
        protocol        = [string]$Destination.protocol
    }
}

function Get-GSASegmentSignature {
    param(
        [string]$DestinationHost,
        [string]$DestinationType,
        [string]$Protocol,
        $Ports
    )
    $portsNorm = (@($Ports) | Sort-Object) -join ','
    return ("$DestinationHost|$DestinationType|$Protocol|$portsNorm").ToLowerInvariant()
}

function Get-GSADestinationSignatureFromSpec {
    param([hashtable]$Destination)
    return (Get-GSASegmentSignature -DestinationHost ([string]$Destination.host) -DestinationType ([string]$Destination.type) -Protocol ([string]$Destination.protocol) -Ports @($Destination.ports))
}
