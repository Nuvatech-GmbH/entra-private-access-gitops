function Connect-GSAEnvironment {
    <#
    .SYNOPSIS
    Stellt eine Microsoft Graph Verbindung für Private Access Automation her.
    .PARAMETER AuthenticationMode
    AzureCli (Standard, nach azure/login OIDC), AccessToken, oder Interactive.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [ValidateSet('AzureCli', 'AccessToken', 'Interactive')]
        [string]$AuthenticationMode = 'AzureCli',

        [SecureString]$GraphAccessToken,

        [string]$ClientId,

        [string[]]$InteractiveScopes = @(
            'https://graph.microsoft.com/Application.ReadWrite.All',
            'https://graph.microsoft.com/Directory.ReadWrite.All',
            'https://graph.microsoft.com/AppRoleAssignment.ReadWrite.All'
        )
    )

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null

    switch ($AuthenticationMode) {
        'AzureCli' {
            $json = & az account get-access-token --resource-type ms-graph --tenant $TenantId 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Azure CLI Graph-Token konnte nicht abgerufen werden. Stellen Sie sicher, dass `az login` bzw. OIDC-Login erfolgreich war."
            }
            $obj = $json | ConvertFrom-Json
            $sec = ConvertTo-SecureString -String $obj.accessToken -AsPlainText -Force
            Connect-MgGraph -TenantId $TenantId -AccessToken $sec -NoWelcome | Out-Null
        }
        'AccessToken' {
            if (-not $GraphAccessToken) {
                throw 'GraphAccessToken ist erforderlich bei AuthenticationMode=AccessToken.'
            }
            Connect-MgGraph -TenantId $TenantId -AccessToken $GraphAccessToken -NoWelcome | Out-Null
        }
        'Interactive' {
            if ($ClientId) {
                Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -Scopes $InteractiveScopes -NoWelcome | Out-Null
            }
            else {
                Connect-MgGraph -TenantId $TenantId -Scopes $InteractiveScopes -NoWelcome | Out-Null
            }
        }
        default {
            throw "Unbekannter AuthenticationMode: $AuthenticationMode"
        }
    }

    $ctx = Get-MgContext
    Write-GSAStructuredLog -Level 'Information' -Message 'Microsoft Graph verbunden.' -Data @{
        tenantId = $ctx.TenantId
        authType = $AuthenticationMode
        clientId = $ctx.ClientId
    }
}
