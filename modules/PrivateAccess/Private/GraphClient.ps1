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

function Get-GSAGraphErrorFromRecord {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($ErrorRecord.Exception.Message) {
        $parts.Add([string]$ErrorRecord.Exception.Message) | Out-Null
    }
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $parts.Add([string]$ErrorRecord.ErrorDetails.Message) | Out-Null
        try {
            $json = $ErrorRecord.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop
            if ($json.error) {
                return @{
                    code    = [string]$json.error.code
                    message = [string]$json.error.message
                    raw     = ($parts -join ' | ')
                }
            }
        }
        catch {
            # kein Graph-JSON in ErrorDetails
        }
    }

    try {
        $response = $null
        if ($ErrorRecord.Exception -and $ErrorRecord.Exception.Response) {
            $response = $ErrorRecord.Exception.Response
        }
        elseif ($ErrorRecord.Exception.InnerException -and $ErrorRecord.Exception.InnerException.Response) {
            $response = $ErrorRecord.Exception.InnerException.Response
        }
        if ($response) {
            $stream = $response.GetResponseStream()
            if ($stream -and $stream.CanRead) {
                $reader = [System.IO.StreamReader]::new($stream)
                $body = $reader.ReadToEnd()
                $reader.Dispose()
                if ($body) {
                    $parts.Add($body) | Out-Null
                    $json = $body | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($json.error) {
                        return @{
                            code    = [string]$json.error.code
                            message = [string]$json.error.message
                            raw     = ($parts -join ' | ')
                        }
                    }
                }
            }
        }
    }
    catch {
        # Response-Stream nicht lesbar
    }

    return @{ code = ''; message = ''; raw = ($parts -join ' | ') }
}

function ConvertTo-GSAGraphJsonPrepare {
    param($Value)

    if ($null -eq $Value) { return $null }

    if ($Value -is [string] -or $Value -is [ValueType] -or $Value -is [guid]) {
        return $Value
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $out[$key] = ConvertTo-GSAGraphJsonPrepare -Value $Value[$key]
        }
        return $out
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $list.Add((ConvertTo-GSAGraphJsonPrepare -Value $item)) | Out-Null
        }
        return $list
    }

    return $Value
}

function Repair-GSAGraphJsonArrayProperties {
    param([Parameter(Mandatory)][string]$Json)

    # PowerShell ConvertTo-Json: Ein-Element-Liste wird oft zu "ports":"3389-3389" statt "ports":["3389-3389"]
    $repaired = [regex]::Replace($Json, '"ports"\s*:\s*"([^"]+)"', '"ports":["$1"]')
    return $repaired
}

function ConvertTo-GSAGraphJson {
    <#
    .SYNOPSIS
    ConvertTo-Json mit korrekten JSON-Arrays (PowerShell serialisiert Ein-Element-Arrays sonst als Skalar).
    #>
    param([Parameter(Mandatory)][object]$InputObject)

    $prepared = ConvertTo-GSAGraphJsonPrepare -Value $InputObject
    $json = ConvertTo-Json -InputObject $prepared -Depth 30 -Compress
    return (Repair-GSAGraphJsonArrayProperties -Json $json)
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

    $requestBodyJson = $null
    $params = @{
        Method      = $Method
        Uri         = $RelativeUri
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $requestBodyJson = ConvertTo-GSAGraphJson -InputObject $Body
        $params['Body'] = $requestBodyJson
        $params['ContentType'] = 'application/json'
    }
    if ($Headers.Count -gt 0) {
        $params['Headers'] = $Headers
    }

    if (-not (Get-Module -Name 'Microsoft.Graph.Authentication')) {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null
    }
    if ($requestBodyJson -and $RelativeUri -match 'applicationSegments') {
        Write-GSAStructuredLog -Level 'Information' -Message 'Graph Segment Request-Body' -Data @{ uri = $RelativeUri; body = $requestBodyJson }
    }
    try {
        return Invoke-MgGraphRequest @params
    }
    catch {
        $graphErr = Get-GSAGraphErrorFromRecord -ErrorRecord $_
        $detail = $graphErr.raw
        $codeLine = if ($graphErr.code) { "Graph error.code: $($graphErr.code)`nGraph error.message: $($graphErr.message)`n`n" } else { '' }

        if ($detail -match '\b403\b|Forbidden|Authorization_RequestDenied|insufficient privileges|NotAdminRole') {
            throw @"
Microsoft Graph verweigerte die Operation ($Method $RelativeUri).
${codeLine}Details: $detail

Typische Ursachen für Private Access (onPremisesPublishing):
1) Fehlende Graph Application permission 'OnPremisesPublishingProfiles.ReadWrite.All' (Admin Consent) – häufigste Ursache bei App-only/OIDC.
2) Application permissions ohne Admin Consent: Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All.
3) Zusätzlich Directory-Rolle 'Application Administrator' am Enterprise Application sp-gsa-gitops-prod empfohlen.
4) Halbfertige Ziel-App löschen (PA-NUVATECH-OFFICE-RDP-GERSTHOFEN). Pipeline-App sp-gsa-gitops-prod nicht löschen.
"@
        }

        if ($detail -match '\b400\b|Bad Request') {
            $bodyLine = if ($requestBodyJson) { "`nGesendeter Request-Body: $requestBodyJson`n" } else { '' }
            throw @"
Microsoft Graph lehnte die Anfrage ab ($Method $RelativeUri).
${codeLine}Details: $detail
${bodyLine}
Typische Ursachen für Application Segments:
1) Fehlende Graph Application permission 'Application.ReadWrite.All' (Admin Consent) – für Segmente laut Microsoft Learn erforderlich.
2) Ports als Bereich '3389-3389'; JSON-Feld 'ports' muss ein Array sein.
3) protocol nur 'tcp' oder 'udp' (nicht 'tcp,udp' für ipApplicationSegment).
4) destinationType passt nicht zum host (ipAddress vs. fqdn).
"@
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

function ConvertTo-GSAGraphPortRange {
    <#
    .SYNOPSIS
    Graph erwartet Port-Bereiche als "start-end", z. B. "3389-3389" statt "3389".
    #>
    param([Parameter(Mandatory)][string]$Port)

    $p = $Port.Trim()
    if ($p -match '^\d+$') {
        return "$p-$p"
    }
    if ($p -match '^(\d+)-(\d+)$') {
        return $p
    }
    throw "Ungültiges Port-Format '$Port'. Erwartet: '3389' oder '3389-3390'."
}

function New-GSASegmentPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Destination
    )

    $portList = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @($Destination.ports)) {
        $portList.Add((ConvertTo-GSAGraphPortRange -Port ([string]$p))) | Out-Null
    }

    $protocol = [string]$Destination.protocol
    if ($protocol -eq 'tcp,udp') {
        throw "protocol 'tcp,udp' wird von ipApplicationSegment nicht unterstützt. Legen Sie zwei destinations an (tcp und udp) oder nutzen Sie nur tcp/udp."
    }

    return @{
        '@odata.type'     = '#microsoft.graph.ipApplicationSegment'
        destinationHost   = [string]$Destination.host
        destinationType   = [string]$Destination.type
        ports             = $portList
        protocol          = $protocol
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
