function Get-GSAPrivateAccessApplication {
    <#
    .SYNOPSIS
    Liest eine Private Access Anwendung aus Microsoft Graph (Application + Service Principal IDs).
    #>
    [CmdletBinding()]
    param(
        [string]$ApplicationId,
        [string]$DisplayName,
        [string]$CorrelationId = (New-GSACorrelationId)
    )

    if (-not $ApplicationId -and -not $DisplayName) {
        throw 'Geben Sie ApplicationId oder DisplayName an.'
    }

    if ($ApplicationId) {
        $app = Get-GSAApplicationById -ApplicationId $ApplicationId
    }
    else {
        $apps = Get-GSAApplicationByDisplayName -DisplayName $DisplayName
        if ($apps.Count -eq 0) { return $null }
        if ($apps.Count -gt 1) {
            Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message 'Mehrere Applications mit gleichem displayName gefunden; es wird die erste ID verwendet.' -Data @{ displayName = $DisplayName; ids = ($apps | ForEach-Object id) }
        }
        $app = Get-GSAApplicationById -ApplicationId $apps[0].id
    }

    $spUri = "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId eq '$($app.appId)'&`$select=id,appId,displayName"
    $sps = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $spUri }
    $sp = @($sps.value) | Select-Object -First 1

    return [pscustomobject]@{
        ApplicationId         = [string]$app.id
        AppId                 = [string]$app.appId
        DisplayName           = [string]$app.displayName
        ServicePrincipalId    = [string]$sp.id
        OnPremisesPublishing  = $app.onPremisesPublishing
    }
}
