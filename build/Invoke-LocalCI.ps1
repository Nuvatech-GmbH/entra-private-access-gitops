Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-Module powershell-yaml, Pester, PSScriptAnalyzer, Microsoft.Graph.Authentication -Scope CurrentUser -Force

$repo = Split-Path $PSScriptRoot -Parent
$settings = Join-Path $repo 'PSScriptAnalyzerSettings.psd1'
$sa = @()
foreach ($p in @((Join-Path $repo 'modules'), (Join-Path $repo 'scripts'))) {
    $sa += @(Invoke-ScriptAnalyzer -Path $p -Recurse -Severity @('Error','Warning') -Settings $settings)
}
if ($sa) {
    $sa | Format-Table -AutoSize
    throw "PSScriptAnalyzer: $($sa.Count) Befunde"
}

& (Join-Path $repo 'scripts/validate/Invoke-GSAValidation.ps1') -RepoRoot $repo

Import-Module Pester -MinimumVersion 5.0.0
Invoke-Pester -Path (Join-Path $repo 'tests/unit') -CI

Write-Host 'OK'
