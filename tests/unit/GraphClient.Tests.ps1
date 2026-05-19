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
