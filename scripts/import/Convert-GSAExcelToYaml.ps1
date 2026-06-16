#Requires -Version 7.0
<#
.SYNOPSIS
Konvertiert Firewall-Freischaltungen aus Excel/CSV in Private-Access-YAML-Dateien.

.DESCRIPTION
Liest das Tabellenblatt "Firewall" (oder CSV-Export) ein, normalisiert Ziele/Ports/Protokolle
und erzeugt pro Regelblock (Nr. + Einheit) eine YAML-Datei gemäß gsa.gitops/v1.

.EXAMPLE
./scripts/import/Convert-GSAExcelToYaml.ps1 -InputPath ./import/excel/firewall-rules.xlsx

.EXAMPLE
./scripts/import/Convert-GSAExcelToYaml.ps1 -InputPath ./import/excel/firewall.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$InputPath,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$OutputPath = (Join-Path $RepoRoot 'import' 'output' 'generated'),

    [string]$LogPath = (Join-Path $RepoRoot 'import' 'logs'),

    [string]$DefaultsPath = (Join-Path $RepoRoot 'import' 'mappings' 'defaults.json'),

    [string]$ConnectorGroupsPath = (Join-Path $RepoRoot 'import' 'mappings' 'connector-groups.json'),

    [string]$EntraGroupsPath = (Join-Path $RepoRoot 'import' 'mappings' 'entra-groups.json'),

    [string]$WorksheetName = 'Firewall',

    [switch]$SkipValidation,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Private' 'ImportParsers.ps1')

function Read-GSAImportJsonFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Mapping-Datei fehlt: $Path (Beispiel aus *.example kopieren)."
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json)
}

function Get-GSAImportColumnIndex {
    param(
        [Parameter(Mandatory)]$Headers,
        [Parameter(Mandatory)][string[]]$Candidates
    )

    for ($i = 0; $i -lt $Headers.Count; $i++) {
        $h = ([string]$Headers[$i]).Trim().ToLowerInvariant()
        foreach ($c in $Candidates) {
            if ($h -eq $c.ToLowerInvariant()) { return $i }
        }
    }
    return -1
}

function Read-GSAImportTableRows {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$WorksheetName
    )

    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -eq '.csv') {
        return @(Import-Csv -LiteralPath $Path -Encoding UTF8)
    }

    if ($ext -in '.xlsx', '.xlsm', '.xltx') {
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            throw @"
Für XLSX wird das Modul 'ImportExcel' benötigt:
  Install-Module ImportExcel -Scope CurrentUser -Force

Alternativ: Excel-Blatt '$WorksheetName' als CSV speichern und -InputPath ./import/excel/firewall.csv verwenden.
"@
        }
        Import-Module ImportExcel -ErrorAction Stop | Out-Null
        return @(Import-Excel -Path $Path -WorksheetName $WorksheetName -DataOnly)
    }

    throw "Nicht unterstütztes Format '$ext'. Erlaubt: .xlsx, .xlsm, .csv"
}

function Get-GSAImportCellValue {
    param(
        [Parameter(Mandatory)]$Row,
        [int]$Index,
        [string[]]$PropertyNames
    )

    if ($Index -ge 0) {
        $props = @($Row.PSObject.Properties.Name)
        if ($Index -lt $props.Count) {
            $val = $Row.($props[$Index])
            if ($null -ne $val -and -not [string]::IsNullOrWhiteSpace([string]$val)) {
                return ([string]$val).Trim()
            }
        }
    }

    foreach ($name in $PropertyNames) {
        $prop = $Row.PSObject.Properties[$name]
        if ($prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return ([string]$prop.Value).Trim()
        }
    }
    return $null
}

function Write-GSAImportReport {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Report
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
}

function ConvertTo-GSAImportYamlDocument {
    param(
        [Parameter(Mandatory)][hashtable]$Application
    )

    if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
        throw "Modul 'powershell-yaml' fehlt. Install-Module powershell-yaml -Scope CurrentUser"
    }
    Import-Module powershell-yaml -ErrorAction Stop | Out-Null
    return (ConvertTo-Yaml -Data $Application -Depth 20)
}

# --- Start ---

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Eingabedatei nicht gefunden: $InputPath"
}

$defaults = Read-GSAImportJsonFile -Path $DefaultsPath
$connectorMap = @{}
(Read-GSAImportJsonFile -Path $ConnectorGroupsPath).PSObject.Properties |
    Where-Object { $_.Name -notlike '_*' } |
    ForEach-Object { $connectorMap[$_.Name] = [string]$_.Value }

$entraMap = @{}
(Read-GSAImportJsonFile -Path $EntraGroupsPath).PSObject.Properties |
    Where-Object { $_.Name -notlike '_*' } |
    ForEach-Object { $entraMap[$_.Name] = [string]$_.Value }

$rows = Read-GSAImportTableRows -Path $InputPath -WorksheetName $WorksheetName
if (-not $rows) { throw 'Keine Datenzeilen gelesen.' }

$first = $rows[0]
$headers = @($first.PSObject.Properties.Name)
$colNr = Get-GSAImportColumnIndex -Headers $headers -Candidates @('Nr.', 'Nr', 'Nummer', 'ID')
$colRolle = Get-GSAImportColumnIndex -Headers $headers -Candidates @('Admin Rolle', 'AdminRolle', 'Rolle')
$colZiel = Get-GSAImportColumnIndex -Headers $headers -Candidates @('Ziel (DNS-Name/IP/Netze)', 'Ziel', 'Destination')
$colPort = Get-GSAImportColumnIndex -Headers $headers -Candidates @('Port', 'Ports')
$colProto = Get-GSAImportColumnIndex -Headers $headers -Candidates @('Protokoll', 'Protocol')
$colEinheit = Get-GSAImportColumnIndex -Headers $headers -Candidates @('Einheit', 'Unit', 'Standort')

$missingCols = @()
if ($colRolle -lt 0) { $missingCols += 'Admin Rolle' }
if ($colZiel -lt 0) { $missingCols += 'Ziel' }
if ($colPort -lt 0) { $missingCols += 'Port' }
if ($colProto -lt 0) { $missingCols += 'Protokoll' }
if ($missingCols) { throw "Pflichtspalten fehlen: $($missingCols -join ', ')" }

$report = [ordered]@{
    inputPath   = (Resolve-Path -LiteralPath $InputPath).Path
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    applications = @()
    errors      = @()
    warnings    = @()
    stats       = [ordered]@{
        rowsRead           = $rows.Count
        applicationsBuilt  = 0
        destinationsBuilt  = 0
        rowsSkipped        = 0
    }
}

$groups = [ordered]@{}
$lastNr = $null
$lastRolle = $null
$lastEinheit = $null

foreach ($row in $rows) {
    $nr = Get-GSAImportCellValue -Row $row -Index $colNr -PropertyNames @('Nr.', 'Nr')
    $rolle = Get-GSAImportCellValue -Row $row -Index $colRolle -PropertyNames @('Admin Rolle', 'AdminRolle', 'Rolle')
    $einheit = Get-GSAImportCellValue -Row $row -Index $colEinheit -PropertyNames @('Einheit', 'Unit')
    $zielRaw = Get-GSAImportCellValue -Row $row -Index $colZiel -PropertyNames @('Ziel (DNS-Name/IP/Netze)', 'Ziel')
    $portRaw = Get-GSAImportCellValue -Row $row -Index $colPort -PropertyNames @('Port', 'Ports')
    $protoRaw = Get-GSAImportCellValue -Row $row -Index $colProto -PropertyNames @('Protokoll', 'Protocol')

    if ($nr) { $lastNr = $nr }
    else { $nr = $lastNr }

    if ($rolle) { $lastRolle = $rolle }
    else { $rolle = $lastRolle }

    if ($einheit) { $lastEinheit = $einheit }
    else { $einheit = $lastEinheit }

    if ([string]::IsNullOrWhiteSpace($rolle) -and [string]::IsNullOrWhiteSpace($zielRaw) -and [string]::IsNullOrWhiteSpace($portRaw)) {
        $report.stats.rowsSkipped++
        continue
    }

    if ([string]::IsNullOrWhiteSpace($rolle)) {
        $report.errors += "Zeile ohne Admin Rolle (Ziel='$zielRaw', Port='$portRaw')."
        continue
    }

    $groupKey = if ($nr) { "$nr|$einheit" } else { "$rolle|$einheit" }
    if (-not $groups.Contains($groupKey)) {
        $groups[$groupKey] = [ordered]@{
            nr       = $nr
            rolle    = $rolle
            einheit  = $einheit
            rows     = [System.Collections.Generic.List[object]]::new()
        }
    }

    $groups[$groupKey].rows.Add([ordered]@{
            zielRaw   = $zielRaw
            portRaw   = $portRaw
            protoRaw  = $protoRaw
        }) | Out-Null
}

$generatedApps = [System.Collections.Generic.List[object]]::new()

foreach ($entry in $groups.GetEnumerator()) {
    $g = $entry.Value
    $appErrors = [System.Collections.Generic.List[string]]::new()
    $appWarnings = [System.Collections.Generic.List[string]]::new()
    $destinations = [System.Collections.Generic.List[hashtable]]::new()

    $principalName = Resolve-GSAImportMappingValue -Map $entraMap -Key ([string]$g.rolle)
    if (-not $principalName) {
        $appErrors.Add("Keine Entra-Gruppe für Admin Rolle '$($g.rolle)' in $EntraGroupsPath.") | Out-Null
    }

    $connectorGroup = Resolve-GSAImportMappingValue -Map $connectorMap -Key ([string]$g.einheit) -Fallback ([string]$defaults.defaultConnectorGroup)
    if ([string]::IsNullOrWhiteSpace($connectorGroup)) {
        $appErrors.Add("Keine Connector Group für Einheit '$($g.einheit)'.") | Out-Null
    }

    foreach ($r in $g.rows) {
        $ziel = ConvertFrom-GSAExcelZiel -Text $r.zielRaw
        if ($ziel.warning) { $appWarnings.Add($ziel.warning) | Out-Null }
        if (-not $ziel.ok) {
            if ($r.zielRaw -or $r.portRaw) {
                $appErrors.Add("Ziel nicht parsebar: '$($r.zielRaw)'") | Out-Null
            }
            continue
        }

        $ports = ConvertFrom-GSAExcelPortTokens -Text $r.portRaw
        if (-not $ports) {
            $appErrors.Add("Keine Ports parsebar für Ziel '$($ziel.host)' (Port-Zelle: '$($r.portRaw)').") | Out-Null
            continue
        }

        $protocols = ConvertFrom-GSAExcelProtokoll -Text $r.protoRaw
        if (-not $protocols) {
            $appErrors.Add("Protokoll nicht erkannt für Ziel '$($ziel.host)' (Wert: '$($r.protoRaw)').") | Out-Null
            continue
        }

        foreach ($protocol in $protocols) {
            $destinations.Add(@{
                    host     = $ziel.host
                    type     = $ziel.type
                    ports    = $ports
                    protocol = $protocol
                }) | Out-Null
        }
    }

    $destinationsFinal = @(Merge-GSAImportedDestinations -Destinations $destinations)
    if ($appErrors.Count -gt 0 -or -not $destinationsFinal) {
        foreach ($e in $appErrors) { $report.errors += "[Gruppe $($entry.Key)] $e" }
        foreach ($w in $appWarnings) { $report.warnings += "[Gruppe $($entry.Key)] $w" }
        continue
    }

    $appName = ConvertTo-GSAImportedApplicationName -AdminRolle $g.rolle -Einheit $g.einheit -Nr $g.nr
    $fileName = ConvertTo-GSAImportedFileName -ApplicationName $appName
    $changeRef = if ($g.nr) { "$($defaults.changeReferencePrefix)-$($g.nr)" } else { "$($defaults.changeReferencePrefix)-$appName" }

    $doc = [ordered]@{
        apiVersion = 'gsa.gitops/v1'
        kind       = 'PrivateAccessApplication'
        metadata   = [ordered]@{
            name            = $appName
            description     = "Import Excel Firewall Nr. $($g.nr) – $($g.rolle) ($($g.einheit))"
            owners          = @($defaults.owners)
            changeReference = $changeRef
            tags            = [ordered]@{
                excelNr    = if ($g.nr) { [string]$g.nr } else { '' }
                adminRolle = [string]$g.rolle
                einheit    = if ($g.einheit) { [string]$g.einheit } else { '' }
                sourceSheet = [string]$defaults.sourceSheet
            }
        }
        spec = [ordered]@{
            applicationType           = [string]$defaults.applicationType
            isAccessibleViaZTNAClient = [bool]$defaults.isAccessibleViaZTNAClient
            connectorGroup            = $connectorGroup
            destinations              = @($destinationsFinal | ForEach-Object {
                    [ordered]@{
                        host     = $_.host
                        type     = $_.type
                        ports    = @($_.ports)
                        protocol = $_.protocol
                    }
                })
            assignments = @(
                [ordered]@{
                    principalType = [string]$defaults.principalType
                    principalName = $principalName
                }
            )
        }
    }

    foreach ($w in $appWarnings) { $report.warnings += "[$appName] $w" }

    $outFile = Join-Path $OutputPath $fileName
    $yamlText = ConvertTo-GSAImportYamlDocument -Application $doc

    if ($PSCmdlet.ShouldProcess($outFile, 'YAML schreiben')) {
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        Set-Content -LiteralPath $outFile -Value $yamlText -Encoding utf8
    }

    $report.applications += [ordered]@{
        name             = $appName
        file             = $fileName
        nr               = $g.nr
        adminRolle       = $g.rolle
        einheit          = $g.einheit
        destinationCount = $destinationsFinal.Count
        principalName    = $principalName
        connectorGroup   = $connectorGroup
    }
    $report.stats.applicationsBuilt++
    $report.stats.destinationsBuilt += $destinationsFinal.Count
    $generatedApps.Add([pscustomobject]@{ Name = $appName; Path = $outFile; Destinations = $destinationsFinal.Count }) | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not (Test-Path -LiteralPath $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}
$reportPath = Join-Path $LogPath "import-report-$timestamp.json"
Write-GSAImportReport -Path $reportPath -Report $report

Write-Host ""
Write-Host "Import abgeschlossen." -ForegroundColor Green
Write-Host "  Anwendungen: $($report.stats.applicationsBuilt)"
Write-Host "  Segmente:    $($report.stats.destinationsBuilt)"
Write-Host "  Fehler:      $($report.errors.Count)"
Write-Host "  Warnungen:   $($report.warnings.Count)"
Write-Host "  Report:      $reportPath"
Write-Host "  Output:      $OutputPath"

if ($report.errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Fehler (Auszug):" -ForegroundColor Red
    $report.errors | Select-Object -First 20 | ForEach-Object { Write-Host "  - $_" }
    throw "Import mit $($report.errors.Count) Fehler(n) beendet. YAML nur für fehlerfreie Gruppen erzeugt."
}

if (-not $SkipValidation -and $report.stats.applicationsBuilt -gt 0) {
    Write-Host ""
    Write-Host "Starte Schema-Validierung der erzeugten YAMLs …" -ForegroundColor Cyan
    $validateScript = Join-Path $RepoRoot 'scripts' 'validate' 'Invoke-GSAValidation.ps1'
    if (Test-Path -LiteralPath $validateScript) {
        & $validateScript -ApplicationsPath $OutputPath
    }
}

if ($PassThru) {
    return $generatedApps
}
