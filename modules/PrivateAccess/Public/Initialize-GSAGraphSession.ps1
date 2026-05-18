function Initialize-GSAGraphSession {
    <#
    .SYNOPSIS
    Stellt eine Microsoft Graph Verbindung für Private Access Automation her.
    .PARAMETER EntraTenantId
    Directory (Tenant) ID des Zielmandanten.
  .PARAMETER AuthenticationMode
    AzureCli (Standard), AccessToken oder Interactive.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EntraTenantId,

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

    switch ($AuthenticationMode) {
        'AzureCli' {
            Connect-GSAGraphViaAzureCli -EntraTenantId $EntraTenantId
        }
        'AccessToken' {
            if (-not $GraphAccessToken) {
                throw 'GraphAccessToken ist erforderlich bei AuthenticationMode=AccessToken.'
            }
            Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null
            Connect-MgGraph -AccessToken $GraphAccessToken -NoWelcome | Out-Null
        }
        'Interactive' {
            Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null
            if ($ClientId) {
                Connect-MgGraph -TenantId $EntraTenantId -ClientId $ClientId -Scopes $InteractiveScopes -NoWelcome | Out-Null
            }
            else {
                Connect-MgGraph -TenantId $EntraTenantId -Scopes $InteractiveScopes -NoWelcome | Out-Null
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

function Connect-GSAEnvironment {
    <#
    .SYNOPSIS
    Alias-Kompatibilität – delegiert an Initialize-GSAGraphSession.
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

    $params = @{
        EntraTenantId       = $TenantId
        AuthenticationMode  = $AuthenticationMode
    }
    if ($GraphAccessToken) { $params.GraphAccessToken = $GraphAccessToken }
    if ($ClientId) { $params.ClientId = $ClientId }
    if ($InteractiveScopes) { $params.InteractiveScopes = $InteractiveScopes }

    Initialize-GSAGraphSession @params
}
