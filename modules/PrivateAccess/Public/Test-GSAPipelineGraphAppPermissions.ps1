function Test-GSAPipelineGraphAppPermissions {
    <#
    .SYNOPSIS
    Prüft erforderliche Microsoft Graph Application permissions der Pipeline-App.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CorrelationId
    )

    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $ctx -or -not $ctx.ClientId) {
        Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message 'Graph-Permission-Prüfung übersprungen (kein Kontext).'
        return
    }

    $requiredAppRoles = @(
        'Application.ReadWrite.All'
        'OnPremisesPublishingProfiles.ReadWrite.All'
        'AppRoleAssignment.ReadWrite.All'
    )

    $ourFilter = "appId eq '$($ctx.ClientId)'"
    $ourUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$([uri]::EscapeDataString($ourFilter))&`$select=id,displayName,appId"
    $ourResp = Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $ourUri
    if (-not $ourResp.value -or $ourResp.value.Count -eq 0) {
        throw "Pipeline Service Principal (appId $($ctx.ClientId)) nicht gefunden."
    }
    $ourSp = $ourResp.value[0]

    $graphResourceAppId = '00000003-0000-0000-c000-000000000000'
    $graphFilter = "appId eq '$graphResourceAppId'"
    $graphUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$([uri]::EscapeDataString($graphFilter))&`$select=id,appRoles"
    $graphResp = Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $graphUri
    $graphSp = $graphResp.value[0]

    $assignUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($ourSp.id)/appRoleAssignments?`$select=appRoleId,resourceId"
    $assignments = Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $assignUri
    $graphAssignments = @($assignments.value | Where-Object { $_.resourceId -eq $graphSp.id })

    $assignedRoleValues = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $graphAssignments) {
        $role = $graphSp.appRoles | Where-Object { $_.id -eq $a.appRoleId } | Select-Object -First 1
        if ($role -and $role.value) {
            $assignedRoleValues.Add([string]$role.value) | Out-Null
        }
    }

    $missing = @($requiredAppRoles | Where-Object { $_ -notin $assignedRoleValues })

    Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Pipeline Graph Application permissions (appRoleAssignments).' -Data @{
        servicePrincipalId          = $ourSp.id
        assignedGraphAppRoles       = @($assignedRoleValues)
        missingGraphAppRoles        = $missing
        graphAppRoleAssignmentCount = $graphAssignments.Count
    }

    if ($missing.Count -gt 0) {
        throw @"
Deploy abgebrochen: Der Pipeline-App fehlen Microsoft Graph Application permissions (Admin Consent): $($missing -join ', ').

Pflicht für Private Access GitOps:
- Application.ReadWrite.All (App anlegen + Application Segments)
- OnPremisesPublishingProfiles.ReadWrite.All (onPremisesPublishing / ZTNA)
- AppRoleAssignment.ReadWrite.All (Gruppen-/User-Zuweisungen)

Entra → App registrations → sp-gsa-gitops-prod → API permissions → Microsoft Graph → Application permissions → hinzufügen → Grant admin consent.
"@
    }
}
