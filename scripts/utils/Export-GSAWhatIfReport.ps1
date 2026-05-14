param(
    [Parameter(Mandatory)][string]$ApplicationsPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$TenantId = $env:GSA_TENANT_ID
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

Import-Module (Join-Path $repoRoot 'modules' 'Common' 'Common.psd1') -Force
Import-Module (Join-Path $repoRoot 'modules' 'PrivateAccess' 'PrivateAccess.psd1') -Force

if ([string]::IsNullOrWhiteSpace($TenantId)) {
    throw 'GSA_TENANT_ID ist nicht gesetzt.'
}

Connect-GSAEnvironment -TenantId $TenantId -TokenSource AzureCli

$report = [System.Collections.Generic.List[object]]::new()
foreach ($f in Get-ChildItem -LiteralPath $ApplicationsPath -Filter '*.yaml' -File) {
    $cmp = Compare-GSAState -ConfigurationPath $f.FullName -CorrelationId (New-GSACorrelationId)
    $report.Add([pscustomobject]@{ file = $f.Name; compare = $cmp }) | Out-Null
}

$report | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $OutputPath -Encoding utf8
