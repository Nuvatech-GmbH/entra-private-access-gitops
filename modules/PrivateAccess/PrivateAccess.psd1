@{
    RootModule        = 'PrivateAccess.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b2d4f6a8-0c1d-4e2f-8a9b-0c1d2e3f4a5b'
    Author            = 'Platform Engineering'
    CompanyName       = 'Contoso'
    Copyright         = '(c) Contoso. All rights reserved.'
    Description       = 'Microsoft Entra Private Access (Global Secure Access) Deployment über Microsoft Graph (Beta).'
    PowerShellVersion = '7.0'
    RequiredModules   = @(
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.19.0' }
    )
    NestedModules     = @()
    FunctionsToExport = @(
        'Initialize-GSAGraphSession',
        'Connect-GSAEnvironment',
        'Get-GSAApplicationConfigFiles',
        'Get-GSAPrivateAccessApplication',
        'New-GSAPrivateAccessApplication',
        'Set-GSAPrivateAccessApplication',
        'Remove-GSAPrivateAccessApplication',
        'Compare-GSAState',
        'Test-GSAConfiguration',
    'Invoke-GSADeployment',
    'Test-GSAPipelineEntraRoles',
    'Test-GSAPipelineGraphAppPermissions'
)
}
