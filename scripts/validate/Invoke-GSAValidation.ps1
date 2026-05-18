param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [string]$ApplicationsPath = (Join-Path $RepoRoot 'config' 'applications'),
    [string]$SchemaPath = (Join-Path $RepoRoot 'schemas' 'private-access-application.schema.json'),
    [switch]$SkipSchema,
    [switch]$FailOnWarnings
)

$ErrorActionPreference = 'Stop'

Import-Module powershell-yaml -ErrorAction Stop | Out-Null
Import-Module (Join-Path $RepoRoot 'modules' 'Common' 'Common.psd1') -Force
Import-Module (Join-Path $RepoRoot 'modules' 'PrivateAccess' 'PrivateAccess.psd1') -Force

function Get-RepoDestinationSignature {
    param($Destination)
    $portsNorm = (@($Destination.ports) | Sort-Object) -join ','
    return ("$($Destination.host)|$($Destination.type)|$($Destination.protocol)|$portsNorm").ToLowerInvariant()
}

$correlation = New-GSACorrelationId
Write-GSAStructuredLog -Level 'Information' -CorrelationId $correlation -Message 'Starte Repository-Validierung' -Data @{ repoRoot = $RepoRoot }

$yamlFiles = @(Get-ChildItem -LiteralPath $ApplicationsPath -Filter '*.yaml' -File -ErrorAction SilentlyContinue)
$exampleFiles = @($yamlFiles | Where-Object { $_.Name -like '*.example.yaml' })
$yamlFiles = @($yamlFiles | Where-Object { $_.Name -notlike '*.example.yaml' })
if (-not $yamlFiles) {
    throw "Keine YAML-Dateien gefunden unter: $ApplicationsPath"
}

$issues = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$signatures = @{}

foreach ($ex in $exampleFiles) {
    $warnings.Add("Beispieldatei übersprungen (nicht für Deploy): $($ex.Name)") | Out-Null
}

foreach ($f in $yamlFiles) {
    try {
        if (-not $SkipSchema) {
            Test-GSAConfiguration -Path $f.FullName -SchemaPath $SchemaPath | Out-Null
        }
        else {
            Test-GSAConfiguration -Path $f.FullName -SkipSchema | Out-Null
        }
    }
    catch {
        $issues.Add("[$($f.Name)] Schema/Struktur: $($_.Exception.Message)") | Out-Null
        continue
    }

    $doc = ConvertFrom-Yaml (Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8)
    $name = [string]$doc.metadata.name

    if ($f.BaseName -ne $name -and -not ($f.Name -like '*.example.*')) {
        $warnings.Add("[$($f.Name)] Dateiname weicht von metadata.name ab: '$($f.BaseName)' vs '$name'") | Out-Null
    }

    if ($name -notmatch '^PA-[A-Z0-9][A-Z0-9._-]{2,}$') {
        $issues.Add("[$($f.Name)] Naming: metadata.name entspricht nicht dem Standard PA-<TEAM>-<SYSTEM> (nur Großbuchstaben empfohlen).") | Out-Null
    }

    foreach ($d in @($doc.spec.destinations)) {
        $sig = "$(Get-RepoDestinationSignature $d)|app=$name"
        if ($signatures.ContainsKey($sig)) {
            $issues.Add("Duplikat/Overlap-Risiko: identisches Ziel wie in $($signatures[$sig]) und $($f.Name)") | Out-Null
        }
        else {
            $signatures[$sig] = $f.Name
        }
    }

    foreach ($a in @($doc.spec.assignments)) {
        $principalId = Select-Object -InputObject $a -ExpandProperty principalId -ErrorAction SilentlyContinue
        $principalName = Select-Object -InputObject $a -ExpandProperty principalName -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($principalId) -and [string]::IsNullOrWhiteSpace($principalName)) {
            $issues.Add("[$($f.Name)] assignment ohne principalId/principalName") | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($principalName) -and [string]$a.principalType -eq 'ServicePrincipal') {
            $issues.Add("[$($f.Name)] principalName wird für ServicePrincipal nicht unterstützt") | Out-Null
        }
    }
}

foreach ($w in $warnings) {
    Write-GSAStructuredLog -Level 'Warning' -CorrelationId $correlation -Message $w
}

if ($issues.Count -gt 0) {
    foreach ($i in $issues) {
        Write-GSAStructuredLog -Level 'Error' -CorrelationId $correlation -Message $i
    }
    throw "Validierung fehlgeschlagen ($($issues.Count) Fehler)."
}

if ($FailOnWarnings -and $warnings.Count -gt 0) {
    throw "Validierung fehlgeschlagen wegen Warnungen ($($warnings.Count))."
}

Write-GSAStructuredLog -Level 'Information' -CorrelationId $correlation -Message 'Validierung erfolgreich abgeschlossen.' -Data @{ files = $yamlFiles.Count }
