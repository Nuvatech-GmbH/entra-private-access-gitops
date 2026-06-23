Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-Module powershell-yaml, Pester, PSScriptAnalyzer, Microsoft.Graph.Authentication -Scope CurrentUser -Force

$repo = Split-Path $PSScriptRoot -Parent
$settings = Join-Path $repo 'PSScriptAnalyzerSettings.psd1'
$sa = @()
foreach ($p in @((Join-Path $repo 'modules'), (Join-Path $repo 'scripts'))) {
    $sa += @(Invoke-ScriptAnalyzer -Path $p -Recurse -Settings $settings)
}
$saErrors = @($sa | Where-Object { $_.Severity -eq 'Error' })
if ($saErrors) {
    $saErrors | Format-Table -AutoSize
    throw "PSScriptAnalyzer: $($saErrors.Count) Error(s)"
}
if ($sa) {
    Write-Host "PSScriptAnalyzer: $($sa.Count) Warning(s) (nicht blockierend)."
}

& (Join-Path $repo 'scripts/validate/Invoke-GSAValidation.ps1') -RepoRoot $repo

Import-Module Pester -MinimumVersion 5.0.0
Invoke-Pester -Path (Join-Path $repo 'tests/unit') -CI

Write-Host 'OK'
