function Set-GSAPrivateAccessApplication {
    <#
    .SYNOPSIS
    Aktualisiert eine bestehende Private Access Anwendung idempotent (Publishing, Connector Group, Segmente, Zuweisungen).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][hashtable]$Document,
        [Parameter(Mandatory)][string]$CorrelationId,
        [switch]$RemoveAbsentSegments,
        [switch]$RemoveAbsentAssignments
    )

    $meta = $Document.metadata
    $spec = $Document.spec
    $name = [string]$meta.name

    $applicationId = $null
    if ($meta.graphApplicationId -and -not [string]::IsNullOrWhiteSpace([string]$meta.graphApplicationId)) {
        $applicationId = [string]$meta.graphApplicationId
    }
    else {
        $applicationId = Resolve-GSAApplicationObjectIdByDisplayName -DisplayName $name -CorrelationId $CorrelationId
        if (-not $applicationId) {
            throw "Application '$name' wurde nicht gefunden. Verwenden Sie New-GSAPrivateAccessApplication oder setzen Sie metadata.graphApplicationId."
        }
    }

    if (-not $PSCmdlet.ShouldProcess($applicationId, "Reconcile Private Access application '$name'")) {
        return [pscustomobject]@{ mode = 'WhatIf'; applicationId = $applicationId }
    }

    $null = Get-GSAApplicationById -ApplicationId $applicationId
    $spId = (Get-GSAPrivateAccessApplication -ApplicationId $applicationId -CorrelationId $CorrelationId).ServicePrincipalId

    $appType = ConvertTo-GSAGraphApplicationType -ApplicationType ([string]$spec.applicationType)
    $pipelineSpId = $null
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($ctx -and $ctx.ClientId) {
        $ourFilter = "appId eq '$($ctx.ClientId)'"
        $ourUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$([uri]::EscapeDataString($ourFilter))&`$select=id"
        $ourSp = Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method GET -RelativeUri $ourUri }
        if ($ourSp.value -and @($ourSp.value).Count -gt 0) {
            $pipelineSpId = ConvertTo-GSAGraphObjectIdString -Value $ourSp.value[0].id -ParameterName 'pipelineServicePrincipalId'
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

    $existingSegs = Get-GSAApplicationSegments -ApplicationId $applicationId
    $desired = @($spec.destinations | ForEach-Object { $_ })

    $existingBySig = @{}
    foreach ($s in $existingSegs) {
        $sig = Get-GSASegmentSignature -DestinationHost $s.destinationHost -DestinationType $s.destinationType -Protocol $s.protocol -Ports $s.ports
        $existingBySig[$sig] = $s
    }

    foreach ($d in $desired) {
        $sig = Get-GSADestinationSignatureFromSpec -Destination $d
        if ($existingBySig.ContainsKey($sig)) { continue }

        Invoke-GSARetryableOperation -Action {
            Add-GSAApplicationSegment -ApplicationId $applicationId -Destination $d -CorrelationId $CorrelationId
        } | Out-Null
    }

    if ($RemoveAbsentSegments) {
        $desiredSigs = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($d in $desired) { [void]$desiredSigs.Add((Get-GSADestinationSignatureFromSpec -Destination $d)) }

        foreach ($s in $existingSegs) {
            $sig = Get-GSASegmentSignature -DestinationHost $s.destinationHost -DestinationType $s.destinationType -Protocol $s.protocol -Ports $s.ports
            if (-not $desiredSigs.Contains($sig)) {
                $delUri = "https://graph.microsoft.com/beta/applications/$applicationId/onPremisesPublishing/segmentsConfiguration/microsoft.graph.ipSegmentConfiguration/applicationSegments/$($s.id)"
                Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method DELETE -RelativeUri $delUri } | Out-Null
            }
        }
    }

    $userRoleId = Get-GSADefaultUserAppRoleId -ServicePrincipalId $spId
    $assignments = Get-GSAAppRoleAssignmentsForResource -ServicePrincipalId $spId
    $managed = @($assignments | Where-Object { $_.appRoleId -eq $userRoleId.ToString() })

    $desiredPrincipals = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($a in @($spec.assignments)) {
        $principalGuid = $null
        if ($a.principalId) { $principalGuid = [guid]$a.principalId }
        else { $principalGuid = Resolve-GSAPrincipalId -PrincipalType ([string]$a.principalType) -PrincipalName ([string]$a.principalName) -CorrelationId $CorrelationId }
        [void]$desiredPrincipals.Add($principalGuid.ToString().ToLowerInvariant())
    }

    foreach ($a in @($spec.assignments)) {
        $principalGuid = $null
        if ($a.principalId) {
            $principalGuid = [guid]$a.principalId
        }
        else {
            $principalGuid = Resolve-GSAPrincipalId -PrincipalType ([string]$a.principalType) -PrincipalName ([string]$a.principalName) -CorrelationId $CorrelationId
        }

        $exists = $managed | Where-Object { ([string]$_.principalId).ToLowerInvariant() -eq $principalGuid.ToString().ToLowerInvariant() } | Select-Object -First 1
        if ($exists) { continue }

        $assignmentBody = @{
            principalId   = $principalGuid.ToString()
            principalType = [string]$a.principalType
            appRoleId     = $userRoleId.ToString()
            resourceId    = $spId
        }
        $assignUri = "https://graph.microsoft.com/beta/servicePrincipals/$spId/appRoleAssignments"
        Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method POST -RelativeUri $assignUri -Body $assignmentBody } | Out-Null
    }

    if ($RemoveAbsentAssignments) {
        foreach ($m in $managed) {
            if (-not $desiredPrincipals.Contains(([string]$m.principalId).ToLowerInvariant())) {
                $delUri = "https://graph.microsoft.com/beta/servicePrincipals/$spId/appRoleAssignments/$($m.id)"
                Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method DELETE -RelativeUri $delUri } | Out-Null
            }
        }
    }

    Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message 'Private Access Anwendung aktualisiert.' -Data @{ applicationId = $applicationId }
    return Get-GSAPrivateAccessApplication -ApplicationId $applicationId -CorrelationId $CorrelationId
}
