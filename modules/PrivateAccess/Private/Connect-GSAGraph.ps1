function Connect-GSAGraphViaAzureCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EntraTenantId
    )

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null

    $json = & az account get-access-token --resource-type ms-graph --tenant $EntraTenantId 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI Graph-Token konnte nicht abgerufen werden. Stellen Sie sicher, dass `az login` bzw. OIDC-Login erfolgreich war."
    }

    $obj = $json | ConvertFrom-Json
    $sec = ConvertTo-SecureString -String $obj.accessToken -AsPlainText -Force

    # Nur -AccessToken (kein -TenantId): vermeidet Parameter-Set-Konflikte in Microsoft.Graph.Authentication
    Connect-MgGraph -AccessToken $sec -NoWelcome | Out-Null
}
