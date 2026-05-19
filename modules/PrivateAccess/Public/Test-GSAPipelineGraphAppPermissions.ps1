function Test-GSAPipelineGraphAppPermissions {
    <#
    .SYNOPSIS
    Prüft, ob die Pipeline-App die Application permission OnPremisesPublishingProfiles.ReadWrite.All hat (Admin Consent).
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

    # Microsoft Graph service principal + App Role ID (Application permission)
    $graphResourceAppId = '00000003-0000-0000-c000-000000000000'
    $onPremPublishingReadWriteAppRoleId = '0b57845e-aa49-4e6f-8109-ce654fffa618'
    $applicationReadWriteAllAppRoleId = '1bfefb4e-e0b5-418b-a88f-73fc16691ae5'

    $ourFilter = "appId eq '$($ctx.ClientId)'"
    $ourUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$([uri]::EscapeDataString($ourFilter))&`$select=id,displayName,appId"
    $ourResp = Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $ourUri
    if (-not $ourResp.value -or $ourResp.value.Count -eq 0) {
        throw "Pipeline Service Principal (appId $($ctx.ClientId)) nicht gefunden."
    }
    $ourSp = $ourResp.value[0]

    $graphFilter = "appId eq '$graphResourceAppId'"
    $graphUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$([uri]::EscapeDataString($graphFilter))&`$select=id,appRoles"
    $graphResp = Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $graphUri
    $graphSp = $graphResp.value[0]

    $assignUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($ourSp.id)/appRoleAssignments?`$select=appRoleId,resourceId"
    $assignments = Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $assignUri
    $graphAssignments = @($assignments.value | Where-Object { $_.resourceId -eq $graphSp.id })

    $assignedRoleIds = @($graphAssignments | ForEach-Object { [string]$_.appRoleId })
    $hasOnPremPublishing = $assignedRoleIds -contains $onPremPublishingReadWriteAppRoleId
    $hasAppReadWriteAll = $assignedRoleIds -contains $applicationReadWriteAllAppRoleId

    Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Pipeline Graph Application permissions (appRoleAssignments).' -Data @{
        servicePrincipalId                      = $ourSp.id
        hasApplicationReadWriteAll              = $hasAppReadWriteAll
        hasOnPremisesPublishingProfilesReadWriteAll = $hasOnPremPublishing
        graphAppRoleAssignmentCount             = $graphAssignments.Count
    }

    if (-not $hasOnPremPublishing) {
        throw @"
Deploy abgebrochen: Der Pipeline-App fehlt die Microsoft Graph **Application permission** 'OnPremisesPublishingProfiles.ReadWrite.All' (mit Admin Consent).

Diese Permission ist für Private Access / Application Proxy per App-only-Token erforderlich – 'Application.ReadWrite.All' und Entra-Directory-Rollen am Service Principal reichen dafür in der Praxis oft nicht aus.

Schritte (Entra Portal):
1) App registrations → sp-gsa-gitops-prod → API permissions → Add permission → Microsoft Graph → Application permissions
2) 'OnPremisesPublishingProfiles.ReadWrite.All' hinzufügen
3) 'Grant admin consent for <Tenant>'
4) 5–10 Min. warten, halbfertige App PA-NUVATECH-OFFICE-RDP-GERSTHOFEN löschen, Pipeline erneut starten

Referenz: https://learn.microsoft.com/en-us/graph/permissions-reference#onpremisespublishingprofilesreadwriteall
"@
    }
}
