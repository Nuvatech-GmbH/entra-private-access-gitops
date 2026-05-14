@{
    RootModule        = 'Common.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '6f2c0f2a-0c1b-4c2d-9e3f-1a2b3c4d5e6f'
    Author            = 'Platform Engineering'
    CompanyName       = 'Contoso'
    Copyright         = '(c) Contoso. All rights reserved.'
    Description       = 'Gemeinsame Hilfsfunktionen für strukturierte Logs, Korrelation und resilienten Graph-Zugriff.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'New-GSACorrelationId',
        'Write-GSAStructuredLog',
        'Invoke-GSARetryableOperation',
        'Get-GSAEnvBool'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
