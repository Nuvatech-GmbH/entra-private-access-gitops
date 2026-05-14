function Remove-GSAPrivateAccessApplication {
    <#
    .SYNOPSIS
    Entfernt eine Application aus Microsoft Graph (wirkt als Löschung der App-Registrierung).
    .NOTES
    In Produktionspipelines sollte das Entfernen nur nach explizitem Change erfolgen. Standard ist WhatIf-sicher.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [string]$CorrelationId = (New-GSACorrelationId)
    )

    $uri = "https://graph.microsoft.com/beta/applications/$ApplicationId"
    if (-not $PSCmdlet.ShouldProcess($ApplicationId, 'DELETE application')) {
        return [pscustomobject]@{ mode = 'WhatIf'; applicationId = $ApplicationId }
    }

    Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method DELETE -RelativeUri $uri } | Out-Null
    Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message 'Application wurde gelöscht.' -Data @{ applicationId = $ApplicationId }
}
