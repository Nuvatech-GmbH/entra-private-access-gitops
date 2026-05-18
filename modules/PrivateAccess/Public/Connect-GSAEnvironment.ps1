function Connect-GSAEnvironment {
    <#
    .SYNOPSIS
    Stellt eine Microsoft Graph Verbindung für Private Access Automation her.
    .DESCRIPTION
    Standard (ParameterSet AzureCli): Token via `az account get-access-token` nach azure/login (OIDC).
    #>
    [CmdletBinding(DefaultParameterSetName = 'AzureCli')]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'AccessToken', Mandatory = $true)]
        [SecureString]$GraphAccessToken,

        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$Interactive,

        [Parameter(ParameterSetName = 'Interactive')]
        [string]$ClientId,

        [Parameter(ParameterSetName = 'Interactive')]
        [string[]]$InteractiveScopes = @(
            'https://graph.microsoft.com/Application.ReadWrite.All',
            'https://graph.microsoft.com/Directory.ReadWrite.All',
            'https://graph.microsoft.com/AppRoleAssignment.ReadWrite.All'
        )
    )

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null

    switch ($PSCmdlet.ParameterSetName) {
        'AzureCli' {
            $json = & az account get-access-token --resource-type ms-graph --tenant $TenantId 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Azure CLI Graph-Token konnte nicht abgerufen werden. Stellen Sie sicher, dass `az login` bzw. OIDC-Login erfolgreich war."
            }
            $obj = $json | ConvertFrom-Json
            $sec = ConvertTo-SecureString -String $obj.accessToken -AsPlainText -Force
            Connect-MgGraph -TenantId $TenantId -AccessToken $sec -NoWelcome | Out-Null
            $authLabel = 'AzureCli'
        }
        'AccessToken' {
            Connect-MgGraph -TenantId $TenantId -AccessToken $GraphAccessToken -NoWelcome | Out-Null
            $authLabel = 'AccessToken'
        }
        'Interactive' {
            if (-not $Interactive) {
                throw 'Für den interaktiven Modus muss -Interactive gesetzt sein.'
            }
            if ($ClientId) {
                Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -Scopes $InteractiveScopes -NoWelcome | Out-Null
            }
            else {
                Connect-MgGraph -TenantId $TenantId -Scopes $InteractiveScopes -NoWelcome | Out-Null
            }
            $authLabel = 'Interactive'
        }
    }

    $ctx = Get-MgContext
    Write-GSAStructuredLog -Level 'Information' -Message 'Microsoft Graph verbunden.' -Data @{
        tenantId = $ctx.TenantId
        authType = $authLabel
        clientId = $ctx.ClientId
    }
}
