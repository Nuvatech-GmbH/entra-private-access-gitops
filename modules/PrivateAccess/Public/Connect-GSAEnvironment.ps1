function Connect-GSAEnvironment {
    <#
    .SYNOPSIS
    Stellt eine Microsoft Graph Verbindung für Private Access Automation her.
    .DESCRIPTION
    Unterstützt:
    - AzureCli: Token via `az account get-access-token` (empfohlen nach `azure/login` mit OIDC in GitHub Actions)
    - AccessToken: statischer Token (nur für Notfall-Debugging; bevorzugen Sie AzureCli/OIDC-Pipeline)
    - Interactive: interaktive Anmeldung (Entwicklerrechner)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [ValidateSet('AzureCli','AccessToken','Interactive')][string]$TokenSource = 'AzureCli',
        [string]$ClientId,
        [string[]]$InteractiveScopes = @(
            'https://graph.microsoft.com/Application.ReadWrite.All',
            'https://graph.microsoft.com/Directory.ReadWrite.All',
            'https://graph.microsoft.com/AppRoleAssignment.ReadWrite.All'
        ),
        [SecureString]$AccessToken
    )

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null

    switch ($TokenSource) {
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
            if (-not $AccessToken) { throw 'AccessToken ist erforderlich bei TokenSource=AccessToken.' }
            Connect-MgGraph -TenantId $TenantId -AccessToken $AccessToken -NoWelcome | Out-Null
        }
        'Interactive' {
            if ($ClientId) {
                Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -Scopes $InteractiveScopes -NoWelcome | Out-Null
            }
            else {
                Connect-MgGraph -TenantId $TenantId -Scopes $InteractiveScopes -NoWelcome | Out-Null
            }
        }
    }

    $ctx = Get-MgContext
    Write-GSAStructuredLog -Level 'Information' -Message 'Microsoft Graph verbunden.' -Data @{
        tenantId = $ctx.TenantId
        authType = $TokenSource
        clientId = $ctx.ClientId
    }
}
