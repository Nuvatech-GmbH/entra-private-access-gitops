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
    if ($meta.graphApplicationId) {
        $applicationId = [string]$meta.graphApplicationId
    }
    else {
        $hits = Get-GSAApplicationByDisplayName -DisplayName $name
        if ($hits.Count -eq 0) { throw "Application '$name' wurde nicht gefunden. Verwenden Sie New-GSAPrivateAccessApplication oder setzen Sie metadata.graphApplicationId." }
        if ($hits.Count -gt 1) { throw "Mehrdeutiger Application-Name '$name' ($($hits.Count) Treffer). Setzen Sie metadata.graphApplicationId." }
        $applicationId = [string]$hits[0].id
    }

    if (-not $PSCmdlet.ShouldProcess($applicationId, "Reconcile Private Access application '$name'")) {
        return [pscustomobject]@{ mode = 'WhatIf'; applicationId = $applicationId }
    }

    $null = Get-GSAApplicationById -ApplicationId $applicationId
    $spId = (Get-GSAPrivateAccessApplication -ApplicationId $applicationId -CorrelationId $CorrelationId).ServicePrincipalId

    $appType = ConvertTo-GSAGraphApplicationType -ApplicationType ([string]$spec.applicationType)
    $patch = @{
        onPremisesPublishing = @{
            applicationType               = $appType
            isAccessibleViaZTNAClient     = [bool]$spec.isAccessibleViaZTNAClient
        }
    }
    if ($null -ne $spec.isDnsResolutionEnabled) {
        $patch.onPremisesPublishing.isDnsResolutionEnabled = [bool]$spec.isDnsResolutionEnabled
    }
    $appPatchUri = "https://graph.microsoft.com/beta/applications/$applicationId"
    Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method PATCH -RelativeUri $appPatchUri -Body $patch } | Out-Null

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
        $segUriBase = "https://graph.microsoft.com/beta/applications/$applicationId/onPremisesPublishing/segmentsConfiguration/microsoft.graph.ipSegmentConfiguration/applicationSegments"
        if ($existingBySig.ContainsKey($sig)) { continue }

        $maybeHostMatch = @($existingSegs) | Where-Object {
            $_.destinationHost -eq [string]$d.host -and $_.destinationType -eq [string]$d.type
        } | Select-Object -First 1

        $payload = New-GSASegmentPayload -Destination $d
        if ($maybeHostMatch) {
            $patchSegUri = "$segUriBase/$($maybeHostMatch.id)"
            $patchBody = @{
                ports    = @($d.ports)
                protocol = [string]$d.protocol
            }
            Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method PATCH -RelativeUri $patchSegUri -Body $patchBody } | Out-Null
        }
        else {
            Invoke-GSARetryableOperation -Action { Invoke-GSAGraphBetaRequest -Method POST -RelativeUri $segUriBase -Body $payload } | Out-Null
        }
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
