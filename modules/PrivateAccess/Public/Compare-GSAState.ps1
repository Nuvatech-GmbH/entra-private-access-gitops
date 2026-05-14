function Compare-GSAState {
    <#
    .SYNOPSIS
    Vergleicht Desired State (YAML) mit dem aktuellen Microsoft Entra Zustand.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [string]$CorrelationId = (New-GSACorrelationId)
    )

    $doc = ConvertFrom-GSAYamlDocument -Path $ConfigurationPath
    $meta = $doc.metadata
    $spec = $doc.spec
    $name = [string]$meta.name

    $remote = $null
    if ($meta.graphApplicationId) {
        $remote = Get-GSAPrivateAccessApplication -ApplicationId ([string]$meta.graphApplicationId) -CorrelationId $CorrelationId
    }
    else {
        $remote = Get-GSAPrivateAccessApplication -DisplayName $name -CorrelationId $CorrelationId
    }

    if (-not $remote) {
        return [pscustomobject]@{
            inSync      = $false
            status      = 'MissingInEntra'
            message     = "Keine passende Application in Entra gefunden für '$name'."
            correlation = $CorrelationId
        }
    }

    $applicationId = $remote.ApplicationId
    $segments = Get-GSAApplicationSegments -ApplicationId $applicationId

    $desiredSegSigs = [System.Collections.Generic.List[string]]::new()
    foreach ($d in @($spec.destinations)) {
        $desiredSegSigs.Add((Get-GSADestinationSignatureFromSpec -Destination $d)) | Out-Null
    }

    $actualSegSigs = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $segments) {
        $actualSegSigs.Add((Get-GSASegmentSignature -DestinationHost $s.destinationHost -DestinationType $s.destinationType -Protocol $s.protocol -Ports $s.ports)) | Out-Null
    }

    $segDiff = Compare-Object -ReferenceObject ($desiredSegSigs | Sort-Object) -DifferenceObject ($actualSegSigs | Sort-Object)

    $assignments = Get-GSAAppRoleAssignmentsForResource -ServicePrincipalId $remote.ServicePrincipalId
    $userRoleId = Get-GSADefaultUserAppRoleId -ServicePrincipalId $remote.ServicePrincipalId
    $managed = @($assignments | Where-Object { $_.appRoleId -eq $userRoleId.ToString() })

    $desiredPrincipals = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($a in @($spec.assignments)) {
        if ($a.principalId) {
            [void]$desiredPrincipals.Add(([string]$a.principalId).ToLowerInvariant())
        }
        else {
            $rid = Resolve-GSAPrincipalId -PrincipalType ([string]$a.principalType) -PrincipalName ([string]$a.principalName) -CorrelationId $CorrelationId
            [void]$desiredPrincipals.Add($rid.ToString().ToLowerInvariant())
        }
    }

    $assignDiff = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @($desiredPrincipals)) {
        $hit = $managed | Where-Object { ([string]$_.principalId).ToLowerInvariant() -eq $p } | Select-Object -First 1
        if (-not $hit) { $assignDiff.Add("MissingAssignment:$p") | Out-Null }
    }

    $inSync = (-not $segDiff) -and ($assignDiff.Count -eq 0)

    return [pscustomobject]@{
        inSync                 = [bool]$inSync
        status                 = $(if ($inSync) { 'InSync' } else { 'Drift' })
        applicationId          = $applicationId
        servicePrincipalId     = $remote.ServicePrincipalId
        segmentDiff            = $segDiff
        assignmentDiff         = $assignDiff
        correlation            = $CorrelationId
    }
}
