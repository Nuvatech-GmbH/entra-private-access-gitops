Import-Module (Join-Path $PSScriptRoot '..' 'Common' 'Common.psd1') -ErrorAction Stop

$privateScripts = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$publicScripts  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($s in ($privateScripts + $publicScripts)) {
    . $s.FullName
}

Export-ModuleMember -Function @(
    'Connect-GSAEnvironment',
    'Get-GSAPrivateAccessApplication',
    'New-GSAPrivateAccessApplication',
    'Set-GSAPrivateAccessApplication',
    'Remove-GSAPrivateAccessApplication',
    'Compare-GSAState',
    'Test-GSAConfiguration',
    'Invoke-GSADeployment'
)
