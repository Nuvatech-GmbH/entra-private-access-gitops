function Test-GSAPipelineEntraRoles {
    <#
    .SYNOPSIS
    Prüft, ob der angemeldete Pipeline-Service-Principal die Directory-Rolle Application Administrator hat.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CorrelationId
    )

    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $ctx -or -not $ctx.ClientId) {
        Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message 'Pipeline-Rollenprüfung übersprungen (kein Graph-Kontext).'
        return
    }

    $appAdminTemplateId = '9b895d92-2cd3-44c7-9d02-a6ac2d7ea3c3'
    $gsaAdminTemplateId = '55c0af5b-61d4-4518-b95e-817db8dff776'

    $filter = "appId eq '$($ctx.ClientId)'"
    $spUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$([uri]::EscapeDataString($filter))&`$select=id,displayName,appId"

    try {
        $spResp = Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $spUri
    }
    catch {
        Write-GSAStructuredLog -Level 'Warning' -CorrelationId $CorrelationId -Message 'Pipeline-Rollenprüfung: Service Principal nicht lesbar.' -Data @{ error = $_.Exception.Message }
        return
    }

    if (-not $spResp.value -or $spResp.value.Count -eq 0) {
        throw "Pipeline Service Principal mit appId '$($ctx.ClientId)' wurde im Mandanten nicht gefunden. Prüfen Sie GSA_GRAPH_CLIENT_ID und Federated Credential."
    }

    $sp = $spResp.value[0]
    $rolesUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/memberOf/microsoft.graph.directoryRole?`$select=displayName,roleTemplateId"

    try {
        $rolesResp = Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $rolesUri
    }
    catch {
        throw @"
Deploy abgebrochen: Directory-Rollen des Pipeline-Service-Principals konnten nicht gelesen werden.
Fügen Sie der App Registration 'sp-gsa-gitops-prod' die Application permission 'Directory.Read.All' hinzu (Admin Consent), oder weisen Sie dem Service Principal die Rolle 'Application Administrator' zu und warten Sie auf Replikation.

Service Principal Object ID (für Rollenzuweisung): $($sp.id)
Details: $($_.Exception.Message)
"@
    }

    $roles = @($rolesResp.value)
    $roleNames = @($roles | ForEach-Object { $_.displayName })
    $templateIds = @($roles | ForEach-Object { [string]$_.roleTemplateId } | Where-Object { $_ })

    # memberOf liefert oft displayName, aber roleTemplateId kann leer sein – beides prüfen
    $hasAppAdmin = ($roleNames -contains 'Application Administrator') -or
        ($templateIds -contains $appAdminTemplateId)
    $hasGsaAdmin = ($roleNames -contains 'Global Secure Access Administrator') -or
        ($templateIds -contains $gsaAdminTemplateId)

    Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Pipeline Directory-Rollen (memberOf).' -Data @{
        servicePrincipalId                 = $sp.id
        servicePrincipalDisplayName        = $sp.displayName
        appId                              = $sp.appId
        directoryRoles                     = $roleNames
        directoryRoleTemplateIds           = $templateIds
        hasApplicationAdministrator        = $hasAppAdmin
        hasGlobalSecureAccessAdministrator = $hasGsaAdmin
    }

    if (-not $hasAppAdmin) {
        $rolesText = if ($roleNames.Count -gt 0) { ($roleNames -join ', ') } else { '(keine Directory-Rollen erkannt)' }
        throw @"
Deploy abgebrochen: Dem Pipeline-Service-Principal fehlt die Entra-Directory-Rolle 'Application Administrator'.

Erkannte Rollen am SP '$($sp.displayName)': $rolesText
Object ID (Enterprise Application): $($sp.id)
App (client) ID: $($sp.appId)

Hinweise:
- Rolle dem Service Principal zuweisen (Entra → Enterprise applications → sp-gsa-gitops-prod), nicht nur der App Registration und nicht einem Benutzerkonto.
- 'Global Secure Access Administrator' allein reicht für den PATCH onPremisesPublishing in der Regel nicht.
- Nach Zuweisung 10–15 Min. warten.
- Halbfertige Ziel-App unter Enterprise applications löschen (nicht 'sp-gsa-gitops-prod' löschen).
"@
    }
}
