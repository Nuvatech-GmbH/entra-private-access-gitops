function Invoke-GSADeployment {
    <#
    .SYNOPSIS
    Orchestriert Deployment / DryRun für alle Anwendungsdefinitionen in einem Ordner.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ApplicationsPath,
        [switch]$DryRun,
        [switch]$RemoveAbsentSegments,
        [switch]$RemoveAbsentAssignments,
        [string]$CorrelationId = (New-GSACorrelationId)
    )

    $files = Get-ChildItem -LiteralPath $ApplicationsPath -Filter '*.yaml' -File | Where-Object { $_.Name -notlike '.*' }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($f in $files) {
        Write-GSAStructuredLog -Level 'Information' -CorrelationId $CorrelationId -Message "Verarbeite $($f.Name)" -Data @{ path = $f.FullName }

        Test-GSAConfiguration -Path $f.FullName | Out-Null
        $doc = ConvertFrom-GSAYamlDocument -Path $f.FullName

        if ($DryRun) {
            $results.Add([pscustomobject]@{ file = $f.Name; action = 'DryRun'; detail = 'Validiert (keine Graph-Mutationen)' }) | Out-Null
            continue
        }

        $exists = $null
        if ($doc.metadata.graphApplicationId) {
            $exists = Get-GSAPrivateAccessApplication -ApplicationId ([string]$doc.metadata.graphApplicationId) -CorrelationId $CorrelationId
        }
        else {
            $exists = Get-GSAPrivateAccessApplication -DisplayName ([string]$doc.metadata.name) -CorrelationId $CorrelationId
        }

        $wf = @{}
        if ($WhatIfPreference) { $wf['WhatIf'] = $true }

        if (-not $exists) {
            $created = New-GSAPrivateAccessApplication -Document $doc -CorrelationId $CorrelationId @wf
            $results.Add([pscustomobject]@{ file = $f.Name; action = 'Create'; result = $created }) | Out-Null
        }
        else {
            $updated = Set-GSAPrivateAccessApplication -Document $doc -CorrelationId $CorrelationId -RemoveAbsentSegments:$RemoveAbsentSegments -RemoveAbsentAssignments:$RemoveAbsentAssignments @wf
            $results.Add([pscustomobject]@{ file = $f.Name; action = 'Update'; result = $updated }) | Out-Null
        }
    }

    return $results
}
