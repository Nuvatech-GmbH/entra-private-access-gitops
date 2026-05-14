param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [string]$ApplicationsPath = (Join-Path $RepoRoot 'config' 'applications'),
    [ValidateSet('AzureCli','Interactive')][string]$TokenSource = 'AzureCli',
    [switch]$WhatIf,
    [switch]$DryRun,
    [switch]$RemoveAbsentSegments,
    [switch]$RemoveAbsentAssignments
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'modules' 'Common' 'Common.psd1') -Force
Import-Module (Join-Path $RepoRoot 'modules' 'PrivateAccess' 'PrivateAccess.psd1') -Force
Import-Module powershell-yaml -ErrorAction Stop | Out-Null

$tenantId = $env:GSA_TENANT_ID
if ([string]::IsNullOrWhiteSpace($tenantId)) {
    throw 'GSA_TENANT_ID ist nicht gesetzt.'
}

$correlation = New-GSACorrelationId
Write-GSAStructuredLog -Level 'Information' -CorrelationId $correlation -Message 'Starte Produktions-Deployment' -Data @{
    applicationsPath = $ApplicationsPath
    whatIf           = [bool]$WhatIf
    dryRun           = [bool]$DryRun
}

Connect-GSAEnvironment -TenantId $tenantId -TokenSource $TokenSource

$results = Invoke-GSADeployment -ApplicationsPath $ApplicationsPath -DryRun:$DryRun -WhatIf:$WhatIf -RemoveAbsentSegments:$RemoveAbsentSegments -RemoveAbsentAssignments:$RemoveAbsentAssignments -CorrelationId $correlation

if ($env:GITHUB_STEP_SUMMARY) {
    $md = @()
    $md += '## Microsoft Entra Private Access Deployment'
    $md += ''
    $md += '| Datei | Aktion | Details |'
    $md += '| --- | --- | --- |'
    foreach ($r in @($results)) {
        $detail = ''
        if ($r.result) { $detail = ($r.result | ConvertTo-Json -Compress -Depth 6) }
        elseif ($r.detail) { $detail = $r.detail }
        $md += "| $($r.file) | $($r.action) | ``$detail`` |"
    }
    $md -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
}

return $results
