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

    if (-not [string]::IsNullOrWhiteSpace($ApplicationId)) {
        $app = Get-GSAApplicationById -ApplicationId $ApplicationId.Trim()
    }
    else {
        $objectId = Resolve-GSAApplicationObjectIdByDisplayName -DisplayName $DisplayName -CorrelationId $CorrelationId
        if (-not $objectId) { return $null }
        $app = Get-GSAApplicationById -ApplicationId $objectId
    }

    $spFilter = [uri]::EscapeDataString("appId eq '$($app.appId)'")
    $spUri = Format-GSAGraphResourceUri 'https://graph.microsoft.com/beta/servicePrincipals?$filter={0}&$select=id,appId,displayName' $spFilter
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
