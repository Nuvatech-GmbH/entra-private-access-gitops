function Add-GSAApplicationOwnerServicePrincipal {
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$OwnerServicePrincipalId
    )

    $ownersUri = "https://graph.microsoft.com/v1.0/applications/$ApplicationId/owners?`$select=id"
    $existing = Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $ownersUri
    if (@($existing.value).id -contains $OwnerServicePrincipalId) {
        return
    }

    $body = @{
        '@odata.id' = "https://graph.microsoft.com/v1.0/servicePrincipals/$OwnerServicePrincipalId"
    }
    $refUri = "https://graph.microsoft.com/v1.0/applications/$ApplicationId/owners/`$ref"
    Invoke-GSAGraphBetaRequest -Method POST -RelativeUri $refUri -Body $body | Out-Null
}

function Set-GSAOnPremisesPublishing {
    <#
    .SYNOPSIS
    Setzt onPremisesPublishing für Private Access (mehrere Graph-Pfade, falls einer blockiert).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$ApplicationType,
        [Parameter(Mandatory)][bool]$IsAccessibleViaZTNAClient,
        [bool]$IsDnsResolutionEnabled,
        [string]$PipelineServicePrincipalId
    )

    $flatBody = @{
        applicationType           = $ApplicationType
        isAccessibleViaZTNAClient = $IsAccessibleViaZTNAClient
    }
    if ($PSBoundParameters.ContainsKey('IsDnsResolutionEnabled')) {
        $flatBody['isDnsResolutionEnabled'] = $IsDnsResolutionEnabled
    }

    if ($PipelineServicePrincipalId) {
        try {
            Add-GSAApplicationOwnerServicePrincipal -ApplicationId $ApplicationId -OwnerServicePrincipalId $PipelineServicePrincipalId
        }
        catch {
            Write-GSAStructuredLog -Level 'Warning' -Message 'Owner-Zuweisung für Application übersprungen.' -Data @{ error = $_.Exception.Message }
        }
    }

    $nestedBody = @{ onPremisesPublishing = $flatBody }
    $subResourceUri = "https://graph.microsoft.com/beta/applications/$ApplicationId/onPremisesPublishing"
    $applicationUri = "https://graph.microsoft.com/beta/applications/$ApplicationId"

    $attempts = @(
        @{ label = 'PATCH applications/{id}/onPremisesPublishing'; uri = $subResourceUri; body = $flatBody },
        @{ label = 'PATCH applications/{id} (nested)'; uri = $applicationUri; body = $nestedBody }
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($attempt in $attempts) {
        try {
            Invoke-GSAGraphBetaRequest -Method PATCH -RelativeUri $attempt.uri -Body $attempt.body | Out-Null
            Write-GSAStructuredLog -Level 'Information' -Message 'onPremisesPublishing gesetzt.' -Data @{ method = $attempt.label }
            return
        }
        catch {
            $graphErr = Get-GSAGraphErrorFromRecord -ErrorRecord $_
            $errors.Add("$($attempt.label): code=$($graphErr.code) $($graphErr.message)") | Out-Null
        }
    }

    throw "onPremisesPublishing konnte nicht gesetzt werden. Versuche:`n$($errors -join "`n")"
}
