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
    It 'normalisiert ports im Segment-Payload' {
        $payload = New-GSASegmentPayload -Destination @{
            host     = '10.0.1.1'
            type     = 'ipAddress'
            ports    = @('3389')
            protocol = 'tcp'
        }
        @($payload.ports) | Should -Be @('3389-3389')
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
