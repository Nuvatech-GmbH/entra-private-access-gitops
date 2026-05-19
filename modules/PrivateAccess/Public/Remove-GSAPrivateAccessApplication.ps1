function Remove-GSAPrivateAccessApplication {
    <#
    .SYNOPSIS
    Entfernt eine Application aus Microsoft Graph (Soft-Delete) und optional aus dem Papierkorb (Purge).
    .NOTES
    - Standard-Deploy-Pipeline ruft diese Funktion NICHT auf.
    - -PurgeFromRecycleBin ist irreversibel – nur manuell nach Runbook.
    - Siehe docs/operations/application-lifecycle-and-purge.md
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [string]$CorrelationId = (New-GSACorrelationId),
        [switch]$PurgeFromRecycleBin,
        [switch]$RecycleBinOnly
    )

    if (-not $RecycleBinOnly) {
        $uri = "https://graph.microsoft.com/beta/applications/$ApplicationId"
        if (-not $PSCmdlet.ShouldProcess($ApplicationId, 'DELETE application (soft-delete)')) {
            return [pscustomobject]@{ mode = 'WhatIf'; applicationId = $ApplicationId; purge = $PurgeFromRecycleBin.IsPresent }
        }

        try {
            Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method DELETE -RelativeUri $uri } | Out-Null
            Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message 'Application soft-deleted.' -Data @{ applicationId = $ApplicationId }
        }
        catch {
            if (-not $PurgeFromRecycleBin) { throw }
            Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Soft-delete übersprungen (App evtl. bereits im Papierkorb).' -Data @{
                applicationId = $ApplicationId
                error         = $_.Exception.Message
            }
        }
    }

    if ($PurgeFromRecycleBin) {
        $purgeUri = "https://graph.microsoft.com/v1.0/directory/deletedItems/$ApplicationId"
        if (-not $PSCmdlet.ShouldProcess($ApplicationId, 'Purge application from directory/deletedItems (permanent)')) {
            return [pscustomobject]@{ mode = 'WhatIf'; applicationId = $ApplicationId; purge = $true }
        }
        Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method DELETE -RelativeUri $purgeUri } | Out-Null
        Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message 'Application aus deletedItems permanent entfernt (Purge).' -Data @{ applicationId = $ApplicationId }
    }

    return [pscustomobject]@{ applicationId = $ApplicationId; purged = $PurgeFromRecycleBin.IsPresent }
}
