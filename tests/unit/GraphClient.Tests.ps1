BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    . (Join-Path $RepoRoot 'modules/PrivateAccess/Private/GraphClient.ps1')
}

Describe 'ConvertTo-GSAGraphPortRange' {
    It 'wandelt einzelnen Port in Bereich um' {
        ConvertTo-GSAGraphPortRange -Port '3389' | Should -Be '3389-3389'
    }

    It 'lässt Bereich unverändert' {
        ConvertTo-GSAGraphPortRange -Port '3389-3390' | Should -Be '3389-3390'
    }
}

Describe 'New-GSASegmentPayload' {
    It 'normalisiert ports im Segment-Payload (Microsoft-Format ohne @odata.type)' {
        $payload = New-GSASegmentPayload -DestinationHost '10.0.1.1/32' -DestinationType 'ipRangeCidr' -Ports @('3389') -Protocol 'tcp'
        @($payload.ports) | Should -Be @('3389-3389')
        $payload.ContainsKey('@odata.type') | Should -BeFalse
        $payload.destinationHost | Should -Be '10.0.1.1/32'
    }
}

Describe 'Get-GSAGraphSegmentDestinationCandidates' {
    It 'bietet ipRangeCidr/32 als Fallback für einzelne IPv4' {
        $c = Get-GSAGraphSegmentDestinationCandidates -Destination @{
            host = '10.0.1.1'
            type = 'ipAddress'
        }
        @($c | ForEach-Object { $_.destinationType }) | Should -Contain 'ipAddress'
        @($c | ForEach-Object { $_.destinationType }) | Should -Contain 'ipRangeCidr'
    }

}

Describe 'Get-GSASegmentSignature' {
    It 'behandelt Einzelport und Graph-Bereich als gleiche Signatur' {
        $fromYaml = Get-GSASegmentSignature -DestinationHost 'nuvadc01.nuvatech.de' -DestinationType 'fqdn' -Protocol 'tcp' -Ports @('3389')
        $fromGraph = Get-GSASegmentSignature -DestinationHost 'nuvadc01.nuvatech.de' -DestinationType 'fqdn' -Protocol 'tcp' -Ports @('3389-3389')
        $fromYaml | Should -Be $fromGraph
    }
}

Describe 'Get-GSASegmentDuplicateConflictFromText' {
    It 'parst conflictingApplication aus Graph-Fehlertext' {
        $sample = @'
code=Invalid_AppSegments_NonwebApp_Duplicate msg=overlap conflictingApplication={ \"appId\": \"333fe82c-8594-4267-b39b-9efcc12524cf\", \"objectId\": \"e6a1cc59-6ecb-4eef-a275-cbb38c93315b\", \"appName\": \"333fe82c-8594-4267-b39b-9efcc12524cf\" }
'@
        $c = Get-GSASegmentDuplicateConflictFromText -Text $sample
        $c.objectId | Should -Be 'e6a1cc59-6ecb-4eef-a275-cbb38c93315b'
        $c.appId | Should -Be '333fe82c-8594-4267-b39b-9efcc12524cf'
    }
}

Describe 'New-GSASegmentPayload mit port:0' {
    It 'enthält port:0 wenn IncludeDeprecatedPort gesetzt' {
        $payload = New-GSASegmentPayload -DestinationHost '10.0.1.1/32' -DestinationType 'ipRangeCidr' -Ports @('3389') -Protocol 'tcp' -IncludeDeprecatedPort
        $payload.port | Should -Be 0
        @($payload.ports) | Should -Be @('3389-3389')
    }
}

Describe 'Format-GSAGraphResourceUri' {
    It 'lässt OData-Query-Parameter unverändert' {
        $uri = Format-GSAGraphResourceUri 'https://graph.microsoft.com/beta/servicePrincipals/{0}?$select=id,appRoles' '11111111-2222-3333-4444-555555555555'
        $uri | Should -Be 'https://graph.microsoft.com/beta/servicePrincipals/11111111-2222-3333-4444-555555555555?$select=id,appRoles'
    }
}

Describe 'ConvertTo-GSAGraphJson' {
    It 'serialisiert ein einzelnes ports-Element als JSON-Array' {
        $json = ConvertTo-GSAGraphJson -InputObject @{
            destinationHost = '10.0.1.1'
            destinationType = 'ipAddress'
            port            = 0
            ports           = @('3389-3389')
            protocol        = 'tcp'
        }
        $json | Should -Match '"ports"\s*:\s*\['
        $json | Should -Not -Match '"ports"\s*:\s*"3389-3389"'
    }
}
