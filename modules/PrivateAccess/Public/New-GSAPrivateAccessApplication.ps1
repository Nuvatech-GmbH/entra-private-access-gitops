function New-GSAPrivateAccessApplication {
    <#
    .SYNOPSIS
    Erstellt eine neue Private Access Anwendung (Custom Template) und konfiguriert Segmente, Connector Group und Zuweisungen.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][hashtable]$Document,
        [Parameter(Mandatory)][string]$CorrelationId
    )

    $meta = $Document.metadata
    $spec = $Document.spec
    $name = [string]$meta.name

    if (-not $PSCmdlet.ShouldProcess($name, 'Create Private Access application in Entra tenant')) {
        return [pscustomobject]@{ mode = 'WhatIf'; name = $name }
    }

    $templateUri = "https://graph.microsoft.com/v1.0/applicationTemplates/$script:GSA_CustomApplicationTemplateId/instantiate"
    $createBody = @{ displayName = $name }
    $created = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method POST -RelativeUri $templateUri -Body $createBody }

    $applicationId = [string]$created.application.id
    $spId = [string]$created.servicePrincipal.id

    $appType = ConvertTo-GSAGraphApplicationType -ApplicationType ([string]$spec.applicationType)
    $pipelineSpId = $null
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($ctx -and $ctx.ClientId) {
        $ourFilter = "appId eq '$($ctx.ClientId)'"
        $ourUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$([uri]::EscapeDataString($ourFilter))&`$select=id"
        $ourSp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $ourUri }
        if ($ourSp.value -and $ourSp.value.Count -gt 0) {
            $pipelineSpId = [string]$ourSp.value[0].id
        }
    }

    $pubParams = @{
        ApplicationId               = $applicationId
        ApplicationType             = $appType
        IsAccessibleViaZTNAClient   = [bool]$spec.isAccessibleViaZTNAClient
        PipelineServicePrincipalId  = $pipelineSpId
    }
    if ($null -ne $spec.isDnsResolutionEnabled) {
        $pubParams['IsDnsResolutionEnabled'] = [bool]$spec.isDnsResolutionEnabled
    }

    Invoke-GSARetryableOperation -Action { Set-GSAOnPremisesPublishing @pubParams } | Out-Null

    $cg = Get-GSAConnectorGroupByName -Name ([string]$spec.connectorGroup) -CorrelationId $CorrelationId
    $cgOdataId = "https://graph.microsoft.com/beta/onPremisesPublishingProfiles/applicationproxy/connectorGroups/$($cg.id)"
    $putCgUri = "https://graph.microsoft.com/beta/applications/$applicationId/connectorGroup/`$ref"
    Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method PUT -RelativeUri $putCgUri -Body @{ '@odata.id' = $cgOdataId } } | Out-Null

    foreach ($dest in @($spec.destinations)) {
        $segUri = "https://graph.microsoft.com/beta/applications/$applicationId/onPremisesPublishing/segmentsConfiguration/microsoft.graph.ipSegmentConfiguration/applicationSegments"
        $payload = New-GSASegmentPayload -Destination $dest
        Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method POST -RelativeUri $segUri -Body $payload } | Out-Null
    }

    $userRoleId = Get-GSADefaultUserAppRoleId -ServicePrincipalId $spId
    foreach ($a in @($spec.assignments)) {
        $principalId = $null
        if ($a.principalId) {
            $principalId = [guid]$a.principalId
        }
        else {
            $principalId = Resolve-GSAPrincipalId -PrincipalType ([string]$a.principalType) -PrincipalName ([string]$a.principalName) -CorrelationId $CorrelationId
        }

        $assignmentBody = @{
            principalId   = $principalId.ToString()
            principalType = [string]$a.principalType
            appRoleId     = $userRoleId.ToString()
            resourceId    = $spId
        }
        $assignUri = "https://graph.microsoft.com/beta/servicePrincipals/$spId/appRoleAssignments"
        Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method POST -RelativeUri $assignUri -Body $assignmentBody } | Out-Null
    }

    Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Private Access Anwendung erstellt.' -Data @{
        applicationId = $applicationId
        servicePrincipalId = $spId
        name = $name
    }

    return Get-GSAPrivateAccessApplication -ApplicationId $applicationId -CorrelationId $CorrelationId
}
