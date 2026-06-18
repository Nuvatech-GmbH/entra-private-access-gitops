#Requires -Version 7.0
<#
.SYNOPSIS
Validiert ein Import-Arbeitsbuch (CSV) vor YAML-Export.

.EXAMPLE
./scripts/import/Validate-GSAImportWorkbook.ps1 -InputPath ./import/templates/import-workbook-template.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputPath,

    [string]$Delimiter = ';',

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Private' 'ImportParsers.ps1')

$requiredColumns = @(
    'admin_rolle', 'entra_group_name', 'connector_group',
    'target_type', 'protocol', 'ports', 'review_status', 'needs_clarification'
)

$validTargetTypes = @('fqdn', 'ipAddress', 'ipRangeCidr', 'ipRange', 'dnsSuffix')
$validProtocols = @('tcp', 'udp', 'both')
$validReview = @('pending', 'approved', 'rejected', 'needs_clarification')
$validYesNo = @('yes', 'no')

$issues = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Datei nicht gefunden: $InputPath"
}

$rows = @(Import-Csv -LiteralPath $InputPath -Delimiter $Delimiter -Encoding UTF8)
if (-not $rows) { throw 'Keine Datenzeilen.' }

$headers = @($rows[0].PSObject.Properties.Name)
foreach ($col in $requiredColumns) {
    if ($headers -notcontains $col) {
        $issues.Add("Pflichtspalte fehlt: $col") | Out-Null
    }
}
if ($issues.Count -gt 0) { throw ($issues -join "`n") }

$segmentSigs = @{}

function Test-GSAImportIpv4 {
    param([string]$Value)
    return ($Value -match '^(?:\d{1,3}\.){3}\d{1,3}$')
}

function Test-GSAImportCidr {
    param([string]$Value)
    return ($Value -match '^(?:\d{1,3}\.){3}\d{1,3}/\d{1,2}$')
}

function Test-GSAImportPorts {
    param([string]$PortsText)
    if ([string]::IsNullOrWhiteSpace($PortsText)) { return $false }
    try {
        $parsed = ConvertFrom-GSAImportPortsString -Text $PortsText
        return ($parsed.Count -gt 0)
    }
    catch { return $false }
}

$rowNum = 1
foreach ($row in $rows) {
    $rowNum++
    $prefix = "Zeile $rowNum"

    $rs = ([string]$row.review_status).Trim().ToLowerInvariant()
    $strict = ($rs -eq 'approved')

    foreach ($field in @('admin_rolle', 'entra_group_name', 'connector_group', 'target_type', 'review_status', 'needs_clarification')) {
        if ([string]::IsNullOrWhiteSpace([string]$row.$field)) {
            $issues.Add("$prefix : Pflichtfeld '$field' ist leer.") | Out-Null
        }
    }

    $tt = ([string]$row.target_type).Trim()
    if ($tt -and $validTargetTypes -notcontains $tt) {
        $issues.Add("$prefix : target_type '$tt' ungültig.") | Out-Null
    }

    $proto = ([string]$row.protocol).Trim().ToLowerInvariant()
    if ($strict -and $validProtocols -notcontains $proto) {
        $issues.Add("$prefix : protocol muss 'tcp', 'udp' oder 'both' sein (ist '$($row.protocol)').") | Out-Null
    }
    if (-not $strict -and $proto -and $validProtocols -notcontains $proto) {
        $issues.Add("$prefix : protocol muss 'tcp', 'udp' oder 'both' sein (ist '$($row.protocol)').") | Out-Null
    }

    if ($strict -and -not (Test-GSAImportPorts -PortsText ([string]$row.ports))) {
        $issues.Add("$prefix : ports ungültig (z. B. 443 oder 443,4431,5900-5905).") | Out-Null
    }

    if ($validReview -notcontains $rs) {
        $issues.Add("$prefix : review_status '$($row.review_status)' ungültig.") | Out-Null
    }
    if ($rs -eq 'approved' -and ([string]$row.needs_clarification).Trim().ToLowerInvariant() -eq 'yes') {
        $issues.Add("$prefix : approved und needs_clarification=yes widerspricht sich.") | Out-Null
    }

    $nc = ([string]$row.needs_clarification).Trim().ToLowerInvariant()
    if ($nc -and $validYesNo -notcontains $nc) {
        $issues.Add("$prefix : needs_clarification muss 'yes' oder 'no' sein.") | Out-Null
    }
    if ($nc -eq 'yes' -and [string]::IsNullOrWhiteSpace([string]$row.review_comment)) {
        $warnings.Add("$prefix : needs_clarification=yes ohne review_comment.") | Out-Null
    }

    if ($strict) {
        switch ($tt) {
            'fqdn' {
                if ([string]::IsNullOrWhiteSpace([string]$row.fqdn)) {
                    $issues.Add("$prefix : target_type=fqdn erfordert fqdn.") | Out-Null
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$row.ip_address)) {
                    $warnings.Add("$prefix : fqdn gesetzt – ip_address sollte leer sein (nur ein Zieltyp pro Zeile).") | Out-Null
                }
            }
            'ipAddress' {
                if (-not (Test-GSAImportIpv4 ([string]$row.ip_address))) {
                    $issues.Add("$prefix : target_type=ipAddress erfordert gültige ip_address.") | Out-Null
                }
            }
            'ipRangeCidr' {
                if (-not (Test-GSAImportCidr ([string]$row.cidr_range))) {
                    $issues.Add("$prefix : target_type=ipRangeCidr erfordert cidr_range (z. B. 10.0.0.0/24).") | Out-Null
                }
            }
            'ipRange' {
                if (-not (Test-GSAImportIpv4 ([string]$row.ip_range_start)) -or -not (Test-GSAImportIpv4 ([string]$row.ip_range_end))) {
                    $issues.Add("$prefix : target_type=ipRange erfordert ip_range_start und ip_range_end.") | Out-Null
                }
            }
            'dnsSuffix' {
                if ([string]::IsNullOrWhiteSpace([string]$row.fqdn)) {
                    $issues.Add("$prefix : target_type=dnsSuffix erfordert fqdn (Suffix).") | Out-Null
                }
            }
        }
    }

    if ($rs -eq 'approved') {
        try {
            $appName = ConvertTo-GSAApplicationNameFromImportRow -EntraGroupName ([string]$row.entra_group_name) -ConnectorGroup ([string]$row.connector_group)
        }
        catch {
            $issues.Add("$prefix : Application-Name konnte nicht abgeleitet werden ($($_.Exception.Message)).") | Out-Null
            continue
        }

        $hostVal = switch ($tt) {
            'fqdn' { [string]$row.fqdn }
            'ipAddress' { [string]$row.ip_address }
            'ipRangeCidr' { [string]$row.cidr_range }
            'ipRange' { "$($row.ip_range_start)-$($row.ip_range_end)" }
            'dnsSuffix' { [string]$row.fqdn }
            default { '' }
        }
        $portList = @(ConvertFrom-GSAImportPortsString -Text ([string]$row.ports))
        $portNorm = ($portList -join ',')
        $protoForSig = if ($proto -eq 'both') { 'tcp+udp' } else { $proto }
        $sig = "$appName|$hostVal|$tt|$protoForSig|$portNorm".ToLowerInvariant()
        if ($segmentSigs.ContainsKey($sig)) {
            $warnings.Add("$prefix : identisches Segment wie Zeile $($segmentSigs[$sig]).") | Out-Null
        }
        else { $segmentSigs[$sig] = $rowNum }
    }
}

$byApp = @{}
foreach ($row in $rows) {
    if (([string]$row.review_status).Trim().ToLowerInvariant() -ne 'approved') { continue }
    if ([string]::IsNullOrWhiteSpace([string]$row.entra_group_name) -or [string]::IsNullOrWhiteSpace([string]$row.connector_group)) { continue }
    $app = ConvertTo-GSAApplicationNameFromImportRow -EntraGroupName ([string]$row.entra_group_name) -ConnectorGroup ([string]$row.connector_group)
    if (-not $byApp.ContainsKey($app)) { $byApp[$app] = 0 }
    $byApp[$app]++
}
foreach ($entry in $byApp.GetEnumerator()) {
    if ($entry.Value -gt 500) {
        $issues.Add("Application '$($entry.Key)' hat $($entry.Value) Segmente (>500 Graph-Limit).") | Out-Null
    }
}

Write-Host "Validierung: $($rows.Count) Zeilen"
Write-Host "  Fehler:    $($issues.Count)"
Write-Host "  Warnungen: $($warnings.Count)"
Write-Host "  Apps (approved): $($byApp.Count)"

if ($warnings.Count -gt 0) {
    Write-Host "`nWarnungen:" -ForegroundColor Yellow
    $warnings | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
}

if ($issues.Count -gt 0) {
    Write-Host "`nFehler:" -ForegroundColor Red
    $issues | Select-Object -First 50 | ForEach-Object { Write-Host "  $_" }
    throw "Validierung fehlgeschlagen."
}

Write-Host "`nValidierung erfolgreich." -ForegroundColor Green
if ($PassThru) { return $rows }
