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

function Get-GSAGraphErrorSummary {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    $graphErr = Get-GSAGraphErrorFromRecord -ErrorRecord $ErrorRecord
    if ($graphErr.code -or $graphErr.message) {
        return "code=$($graphErr.code) msg=$($graphErr.message)"
    }
    if ($graphErr.raw) {
        return $graphErr.raw
    }
    return [string]$ErrorRecord
}

function Get-GSASegmentDuplicateConflictFromText {
    <#
    .SYNOPSIS
    Parst Invalid_AppSegments_NonwebApp_Duplicate (IP/Port bereits von anderer App im Mandanten).
    #>
    param([Parameter(Mandatory)][string]$Text)

    if ($Text -notmatch 'Invalid_AppSegments_NonwebApp_Duplicate') {
        return $null
    }

    $conflict = @{
        appId     = ''
        objectId  = ''
        appName   = ''
        graphCode = 'Invalid_AppSegments_NonwebApp_Duplicate'
    }

    if ($Text -match 'conflictingApplication=\{') {
        $jsonFragment = $Text -replace '.*conflictingApplication=', ''
        $jsonFragment = ($jsonFragment -split '\}', 2)[0] + '}'
        $normalized = $jsonFragment -replace '\\"', '"'
        try {
            $parsed = $normalized | ConvertFrom-Json -ErrorAction Stop
            $conflict.appId = [string]$parsed.appId
            $conflict.objectId = [string]$parsed.objectId
            $conflict.appName = [string]$parsed.appName
            return $conflict
        }
        catch {
            # Fallback: Regex
        }
    }

    if ($Text -match '\\"appId\\":\s*\\"([^\\"]+)\\"') { $conflict.appId = $Matches[1] }
    if ($Text -match '\\"objectId\\":\s*\\"([^\\"]+)\\"') { $conflict.objectId = $Matches[1] }
    if ($Text -match '\\"appName\\":\s*\\"([^\\"]+)\\"') { $conflict.appName = $Matches[1] }

    if ($conflict.objectId -or $conflict.appId) {
        return $conflict
    }
    return $null
}

function Format-GSASegmentDuplicateConflictMessage {
    param(
        [Parameter(Mandatory)][hashtable]$Destination,
        [Parameter(Mandatory)]$Conflict,
        [string]$CurrentApplicationId
    )

    $hostValue = [string]$Destination.host
    $ports = (Get-GSAGraphPortListFromSpec -Ports $Destination.ports) -join ','
    $lines = @(
        'Segment-Konflikt im Mandanten (Graph: Invalid_AppSegments_NonwebApp_Duplicate):',
        "Die Kombination aus Ziel ($hostValue) und Port(s) ($ports) / Protokoll ($($Destination.protocol)) ist bereits von einer anderen Private-Access-App belegt.",
        'Pro Mandant darf dieselbe IP+Port-Kombination nur einmal vorkommen – auch über verschiedene Anwendungsnamen hinweg.',
        '',
        'Konflikt-App (im Entra-Portal unter Unternehmensanwendungen suchen/löschen):',
        "  objectId (Enterprise Application): $($Conflict.objectId)",
        "  appId: $($Conflict.appId)",
        "  appName (Anzeige): $($Conflict.appName)"
    )
    if ($CurrentApplicationId) {
        $lines += ''
        $lines += "Die in diesem Lauf neu angelegte Ziel-App (objectId/ApplicationId $CurrentApplicationId) sollten Sie ebenfalls löschen, bevor Sie erneut deployen."
    }
    $lines += ''
    $lines += 'Alternativ: in der YAML eine andere IP oder andere Ports verwenden.'
    return ($lines -join "`n")
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

function Format-GSAGraphResourceUri {
    <#
    .SYNOPSIS
    Baut Graph-URLs mit [string]::Format, damit $filter/$select in OData-Query-Strings nicht als PowerShell-Variablen expandieren.
    #>
    param(
        [Parameter(Mandatory)][string]$Template,
        [object[]]$FormatArguments = @()
    )

    return [string]::Format($Template, $FormatArguments)
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
            $segmentHints = if ($RelativeUri -match 'applicationSegments') {
                @"

Typische Ursachen für Application Segments:
1) Fehlende Graph Application permission 'Application.ReadWrite.All' (Admin Consent) – für Segmente laut Microsoft Learn erforderlich.
2) Ports als Bereich '3389-3389'; JSON-Feld 'ports' muss ein Array sein.
3) protocol nur 'tcp' oder 'udp' (nicht 'tcp,udp' für ipApplicationSegment).
4) destinationType passt nicht zum host (ipAddress vs. fqdn).
"@
            }
            elseif ($RelativeUri -match 'servicePrincipals/\$select|servicePrincipals/\?') {
                @"

Typische Ursachen für Service-Principal-Operationen:
1) Die Service-Principal-ID der Ziel-App fehlt (instantiate-Response ohne servicePrincipal.id) – Pipeline lädt die ID per appId nach.
2) OData-Query-Parameter ($select, $filter) dürfen in der URI nicht als Pfadsegment landen.
"@
            }
            else { '' }
            if ($RelativeUri -match 'applicationSegments') {
                throw $_
            }
            throw @"
Microsoft Graph lehnte die Anfrage ab ($Method $RelativeUri).
${codeLine}Details: $detail
${bodyLine}${segmentHints}
"@
        }
        if ($RelativeUri -match 'applicationSegments') {
            throw $_
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
    $uri = Format-GSAGraphResourceUri 'https://graph.microsoft.com/beta/onPremisesPublishingProfiles/applicationProxy/connectorGroups?$filter={0}' $encoded

    $resp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
    if (-not $resp.value -or $resp.value.Count -eq 0) {
        throw "Connector Group wurde nicht gefunden: '$Name'"
    }
    if ($resp.value.Count -gt 1) {
        Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message "Mehrdeutiger Connector-Group-Name '$Name'; es wird der erste Treffer verwendet." -Data @{ count = $resp.value.Count }
    }
    return $resp.value[0]
}

function Resolve-GSAServicePrincipalId {
    param(
        [string]$ServicePrincipalId,
        [string]$ApplicationAppId,
        [Parameter(Mandatory)][string]$CorrelationId
    )

    if (-not [string]::IsNullOrWhiteSpace($ServicePrincipalId)) {
        return $ServicePrincipalId.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($ApplicationAppId)) {
        throw 'Service-Principal-ID fehlt: Die Template-Instantiate-Response enthielt keine servicePrincipal.id und es wurde keine application.appId übergeben.'
    }

    $filter = [uri]::EscapeDataString("appId eq '$ApplicationAppId'")
    $uri = Format-GSAGraphResourceUri 'https://graph.microsoft.com/v1.0/servicePrincipals?$filter={0}&$select=id' $filter
    $resp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
    if (-not $resp.value -or $resp.value.Count -eq 0) {
        throw "Service Principal für appId '$ApplicationAppId' wurde nicht gefunden."
    }

    $resolvedId = [string]$resp.value[0].id
    Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Service Principal nach appId aufgelöst (instantiate ohne servicePrincipal.id).' -Data @{
        applicationAppId   = $ApplicationAppId
        servicePrincipalId = $resolvedId
    }
    return $resolvedId
}

function Get-GSADefaultUserAppRoleId {
    param([Parameter(Mandatory)][string]$ServicePrincipalId)

    if ([string]::IsNullOrWhiteSpace($ServicePrincipalId)) {
        throw 'ServicePrincipalId ist leer; die AppRole ''User'' kann nicht ermittelt werden.'
    }

    $uri = Format-GSAGraphResourceUri 'https://graph.microsoft.com/beta/servicePrincipals/{0}?$select=id,appRoles' $ServicePrincipalId
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
            $uri = Format-GSAGraphResourceUri 'https://graph.microsoft.com/beta/groups?$filter={0}&$select=id,displayName' $q
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
    if ([string]::IsNullOrWhiteSpace($ServicePrincipalId)) {
        throw 'ServicePrincipalId ist leer; AppRole-Zuweisungen können nicht gelesen werden.'
    }
    $uri = Format-GSAGraphResourceUri 'https://graph.microsoft.com/beta/servicePrincipals/{0}/appRoleAssignedTo' $ServicePrincipalId
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
    # onPremisesPublishing in $select auf /applications?$filter=… führt zu InvalidGuid_BadRequest – Details per GET by id
    $uri = Format-GSAGraphResourceUri 'https://graph.microsoft.com/beta/applications?$filter={0}&$select=id,displayName,appId' $q
    $resp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $uri }
    return @($resp.value)
}

function Resolve-GSAApplicationObjectIdByDisplayName {
    <#
    .SYNOPSIS
    Eindeutige Application objectId zu displayName; wirft bei mehreren Treffern mit gültiger id.
    #>
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$CorrelationId
    )

    $apps = @(Get-GSAApplicationByDisplayName -DisplayName $DisplayName | Where-Object {
            $_.id -and -not [string]::IsNullOrWhiteSpace([string]$_.id)
        })

    if ($apps.Count -eq 0) {
        return $null
    }

    if ($apps.Count -gt 1) {
        $ids = ($apps | ForEach-Object { [string]$_.id }) -join ', '
        throw @"
Mehrere Entra-Applications mit displayName '$DisplayName' (objectIds: $ids).
Bereinigen Sie Duplikate unter Unternehmensanwendungen / App-Registrierungen (inkl. Papierkorb) oder setzen Sie metadata.graphApplicationId in der YAML auf die gewünschte objectId.
"@
    }

    return [string]$apps[0].id
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

function Get-GSAGraphPortListFromSpec {
    param($Ports)

    if ($null -eq $Ports) { return @() }
    if ($Ports -is [string]) { return @($Ports) }
    return @($Ports)
}

function Get-GSASegmentSignature {
    param(
        [string]$DestinationHost,
        [string]$DestinationType,
        [string]$Protocol,
        $Ports
    )

    $portRanges = [System.Collections.Generic.List[string]]::new()
    foreach ($p in (Get-GSAGraphPortListFromSpec -Ports $Ports)) {
        $portRanges.Add((ConvertTo-GSAGraphPortRange -Port ([string]$p))) | Out-Null
    }
    $portsNorm = ($portRanges | Sort-Object) -join ','
    $hostNorm = ([string]$DestinationHost).Trim().ToLowerInvariant()
    return ("$hostNorm|$DestinationType|$Protocol|$portsNorm").ToLowerInvariant()
}

function Get-GSADestinationSignatureFromSpec {
    param([hashtable]$Destination)
    return (Get-GSASegmentSignature -DestinationHost ([string]$Destination.host) -DestinationType ([string]$Destination.type) -Protocol ([string]$Destination.protocol) -Ports $Destination.ports)
}

function Find-GSAApplicationSegmentBySignature {
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$Signature
    )

    foreach ($s in (Get-GSAApplicationSegments -ApplicationId $ApplicationId)) {
        $sig = Get-GSASegmentSignature -DestinationHost $s.destinationHost -DestinationType $s.destinationType -Protocol $s.protocol -Ports $s.ports
        if ($sig -eq $Signature) {
            return $s
        }
    }
    return $null
}

function Get-GSASegmentIdFromGraphResponse {
    param($Response)

    if ($null -eq $Response) { return $null }
    if ($Response.PSObject.Properties['id'] -and $Response.id) {
        return [string]$Response.id
    }
    return $null
}

function Wait-GSAApplicationSegmentBySignature {
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$Signature,
        [int]$MaxAttempts = 5,
        [int]$DelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $found = Find-GSAApplicationSegmentBySignature -ApplicationId $ApplicationId -Signature $Signature
        if ($found) { return $found }
        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    return $null
}

function Get-GSAGraphSegmentDestinationCandidates {
    <#
    .SYNOPSIS
    Liefert destinationHost/destinationType-Varianten (Graph ist bei IP-RDP oft mit ipRangeCidr /32 strikter).
    #>
    param([Parameter(Mandatory)][hashtable]$Destination)

    $hostValue = [string]$Destination.host
    $typeValue = [string]$Destination.type
    $seen = @{}
    $candidates = [System.Collections.Generic.List[hashtable]]::new()

    $addCandidate = {
        param($DestHost, $DestType)
        $key = "$DestHost|$DestType"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $candidates.Add(@{ destinationHost = $DestHost; destinationType = $DestType }) | Out-Null
        }
    }

    & $addCandidate $hostValue $typeValue

    if ($typeValue -eq 'ipAddress' -and $hostValue -match '^(?:\d{1,3}\.){3}\d{1,3}$') {
        & $addCandidate "$hostValue/32" 'ipRangeCidr'
    }

    return @($candidates)
}

function New-GSASegmentPayload {
    param(
        [Parameter(Mandatory)][string]$DestinationHost,
        [Parameter(Mandatory)][string]$DestinationType,
        [Parameter(Mandatory)]$Ports,
        [Parameter(Mandatory)][string]$Protocol,
        [switch]$IncludeDeprecatedPort
    )

    $portList = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @($Ports)) {
        $portList.Add((ConvertTo-GSAGraphPortRange -Port ([string]$p))) | Out-Null
    }

    if ($Protocol -eq 'tcp,udp') {
        throw "protocol 'tcp,udp' wird von ipApplicationSegment nicht unterstützt. Legen Sie zwei destinations an (tcp und udp) oder nutzen Sie nur tcp/udp."
    }

    # Microsoft Learn: POST enthält port:0 zusätzlich zu ports[]
    $body = @{
        destinationHost = $DestinationHost
        destinationType = $DestinationType
        port            = 0
        ports           = $portList
        protocol        = $Protocol
    }
    if (-not $IncludeDeprecatedPort) {
        $body.Remove('port')
    }
    return $body
}

function Add-GSAApplicationSegment {
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][hashtable]$Destination,
        [Parameter(Mandatory)][string]$CorrelationId
    )

    $sigDesired = Get-GSADestinationSignatureFromSpec -Destination $Destination
    $existingSegment = Find-GSAApplicationSegmentBySignature -ApplicationId $ApplicationId -Signature $sigDesired
    if ($existingSegment) {
        Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Application Segment existiert bereits – übersprungen.' -Data @{
            applicationId = $ApplicationId
            signature     = $sigDesired
            segmentId     = $existingSegment.id
        }
        return $existingSegment
    }

    $segUri = "https://graph.microsoft.com/beta/applications/$ApplicationId/onPremisesPublishing/segmentsConfiguration/microsoft.graph.ipSegmentConfiguration/applicationSegments"
    $protocol = [string]$Destination.protocol
    $portList = Get-GSAGraphPortListFromSpec -Ports $Destination.ports
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($dest in (Get-GSAGraphSegmentDestinationCandidates -Destination $Destination)) {
        $variants = @(
            @{ label = 'mit port:0 (Learn-Standard)'; includePort = $true },
            @{ label = 'ohne port-Feld'; includePort = $false }
        )
        foreach ($variant in $variants) {
            $payload = New-GSASegmentPayload -DestinationHost $dest.destinationHost -DestinationType $dest.destinationType `
                -Ports $portList -Protocol $protocol -IncludeDeprecatedPort:($variant.includePort)
            $json = ConvertTo-GSAGraphJson -InputObject $payload
            Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Versuche Application Segment POST' -Data @{
                variant = $variant.label
                host    = $dest.destinationHost
                type    = $dest.destinationType
                body    = $json
            }
            try {
                $created = Invoke-GSAGraphBetaRequest -Method POST -RelativeUri $segUri -Body $payload
                $segmentId = Get-GSASegmentIdFromGraphResponse -Response $created
                $resolved = $null
                if ($segmentId) {
                    $resolved = $created
                }
                else {
                    $found = Wait-GSAApplicationSegmentBySignature -ApplicationId $ApplicationId -Signature $sigDesired
                    if ($found) {
                        $resolved = $found
                        $segmentId = [string]$found.id
                        Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Application Segment erstellt (ID per GET/Reconcile, POST ohne id).' -Data @{
                            segmentId       = $segmentId
                            destinationHost = $dest.destinationHost
                            destinationType = $dest.destinationType
                            postResponse    = if ($created) { ($created | ConvertTo-Json -Compress -Depth 5) } else { '' }
                        }
                    }
                    else {
                        $postPreview = if ($null -eq $created) { '<null>' } else { ($created | ConvertTo-Json -Compress -Depth 5) }
                        throw "Application Segment POST ohne Segment-ID und kein Treffer per GET (Signatur: $sigDesired). POST-Antwort: $postPreview"
                    }
                }
                if (-not $segmentId) {
                    throw 'Application Segment konnte nicht aufgelöst werden.'
                }
                Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Application Segment erstellt.' -Data @{
                    segmentId         = $segmentId
                    destinationHost   = $dest.destinationHost
                    destinationType   = $dest.destinationType
                }
                return $resolved
            }
            catch {
                $errors.Add("$($variant.label) [$($dest.destinationType) $($dest.destinationHost)]: $(Get-GSAGraphErrorSummary -ErrorRecord $_)") | Out-Null
                $found = Find-GSAApplicationSegmentBySignature -ApplicationId $ApplicationId -Signature $sigDesired
                if ($found) {
                    Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Application Segment nach fehlgeschlagenem POST bereits vorhanden (idempotent).' -Data @{
                        segmentId = $found.id
                        variant   = $variant.label
                    }
                    return $found
                }
            }
        }
    }

    $late = Find-GSAApplicationSegmentBySignature -ApplicationId $ApplicationId -Signature $sigDesired
    if ($late) {
        Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Application Segment nach allen Versuchen per GET gefunden.' -Data @{ segmentId = $late.id }
        return $late
    }

    $allErrorsText = $errors -join "`n"
    $duplicate = Get-GSASegmentDuplicateConflictFromText -Text $allErrorsText
    if ($duplicate) {
        Write-GSAStructuredLog -Level 'Error' -CorrelationId $CorrelationId -Message 'Application Segment: Mandantenweiter IP/Port-Konflikt.' -Data $duplicate
        $conflictMsg = Format-GSASegmentDuplicateConflictMessage -Destination $Destination -Conflict $duplicate -CurrentApplicationId $ApplicationId
        throw @"
Application Segment konnte nicht erstellt werden (ApplicationId: $ApplicationId).

$conflictMsg

Technische Details (Graph):
$allErrorsText
"@
    }

    throw @"
Application Segment konnte nicht erstellt werden (ApplicationId: $ApplicationId).
Ziel aus YAML: host=$($Destination.host) type=$($Destination.type) ports=$($Destination.ports -join ',') protocol=$protocol

Versuche und Graph-Antworten:
$allErrorsText

Hinweise:
- Für RDP auf eine einzelne IP empfiehlt sich in YAML: type ipRangeCidr, host 10.0.1.1/32
- Connector Group muss mindestens einen aktiven Connector enthalten
- Private Access / Entra Suite Lizenz im Tenant aktiv
"@
}

