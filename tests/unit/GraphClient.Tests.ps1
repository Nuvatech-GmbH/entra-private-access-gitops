BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    . (Join-Path $RepoRoot 'modules/PrivateAccess/Private/GraphClient.ps1')
}

Describe 'ConvertTo-GSAGraphObjectIdString' {
    It 'wandelt Guid und String in normalisierte ObjectId um' {
        $guid = [guid]'11111111-2222-3333-4444-555555555555'
        ConvertTo-GSAGraphObjectIdString -Value $guid | Should -Be '11111111-2222-3333-4444-555555555555'
        ConvertTo-GSAGraphObjectIdString -Value ' 11111111-2222-3333-4444-555555555555 ' | Should -Be '11111111-2222-3333-4444-555555555555'
    }

    It 'liest id aus verschachteltem Graph-Objekt' {
        $obj = [pscustomobject]@{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
        ConvertTo-GSAGraphObjectIdString -Value $obj | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    }
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

    It 'sendet tcp,udp als ein Graph-Protokoll (RDP)' {
        $payload = New-GSASegmentPayload -DestinationHost 'jumphost.contoso.corp' -DestinationType 'fqdn' -Ports @('3389') -Protocol 'tcp,udp'
        $payload.protocol | Should -Be 'tcp,udp'
        @($payload.ports) | Should -Be @('3389-3389')
    }
}

Describe 'Get-GSAGraphSegmentDestinationCandidates' {
    It 'verwendet Graph-Wire-Typ ip für Einzel-IPv4 ohne CIDR-/32-Fallback' {
        $c = Get-GSAGraphSegmentDestinationCandidates -Destination @{
            host = '10.0.1.1'
            type = 'ipAddress'
        }
        $c[0].destinationType | Should -Be 'ip'
        $c[0].destinationHost | Should -Be '10.0.1.1'
        $c[1].destinationType | Should -Be 'ipAddress'
        @($c | ForEach-Object { $_.destinationType }) | Should -Not -Contain 'ipRangeCidr'
    }

    It 'bietet ipRange-Varianten und ipRangeCidr-Fallback für Start–Ende' {
        $c = Get-GSAGraphSegmentDestinationCandidates -Destination @{
            host = '192.168.178.40-192.168.178.50'
            type = 'ipRange'
        }
        @($c | ForEach-Object { "$($_.destinationType)|$($_.destinationHost)" }) | Should -Contain 'ipRange|192.168.178.40-192.168.178.50'
        @($c | ForEach-Object { $_.destinationType }) | Should -Contain 'ipRangeCidr'
        ($c | Where-Object { $_.destinationType -eq 'ipRangeCidr' } | Select-Object -First 1).destinationHost | Should -Be '192.168.178.32/27'
    }
}

Describe 'Get-GSAGraphMinimalIpv4CidrForRange' {
    It 'berechnet kleinstes CIDR für IP-Bereich' {
        Get-GSAGraphMinimalIpv4CidrForRange -StartIp '10.0.3.10' -EndIp '10.0.3.20' | Should -Be '10.0.3.0/27'
    }
}

Describe 'Get-GSASegmentSignature' {
    It 'behandelt Einzelport und Graph-Bereich als gleiche Signatur' {
        $fromYaml = Get-GSASegmentSignature -DestinationHost 'dc01.contoso.corp' -DestinationType 'fqdn' -Protocol 'tcp' -Ports @('3389')
        $fromGraph = Get-GSASegmentSignature -DestinationHost 'dc01.contoso.corp' -DestinationType 'fqdn' -Protocol 'tcp' -Ports @('3389-3389')
        $fromYaml | Should -Be $fromGraph
    }

    It 'normalisiert ip, ipAddress und ipRangeCidr/32 für Einzel-IPv4' {
        $yaml = Get-GSASegmentSignature -DestinationHost '10.0.1.1' -DestinationType 'ipAddress' -Protocol 'tcp,udp' -Ports @('3389')
        $graphIp = Get-GSASegmentSignature -DestinationHost '10.0.1.1' -DestinationType 'ip' -Protocol 'tcp,udp' -Ports @('3389-3389')
        $graphCidr = Get-GSASegmentSignature -DestinationHost '10.0.1.1/32' -DestinationType 'ipRangeCidr' -Protocol 'tcp,udp' -Ports @('3389-3389')
        $yaml | Should -Be $graphIp
        $yaml | Should -Be $graphCidr
    }
}

Describe 'Test-GSASegmentRequiresDestinationTypeRepair' {
    It 'erkennt CIDR/32 als Reparaturbedarf für YAML ipAddress' {
        $segment = [pscustomobject]@{
            id              = 'seg-1'
            destinationHost = '10.0.1.1/32'
            destinationType = 'ipRangeCidr'
        }
        $dest = @{ host = '10.0.1.1'; type = 'ipAddress'; ports = @('3389'); protocol = 'tcp' }
        Test-GSASegmentRequiresDestinationTypeRepair -Segment $segment -Destination $dest | Should -BeTrue
    }

    It 'erkennt Graph ip als konsistent zu YAML ipAddress' {
        $segment = [pscustomobject]@{
            id              = 'seg-1'
            destinationHost = '10.0.1.1'
            destinationType = 'ip'
        }
        $dest = @{ host = '10.0.1.1'; type = 'ipAddress'; ports = @('3389'); protocol = 'tcp' }
        Test-GSASegmentRequiresDestinationTypeRepair -Segment $segment -Destination $dest | Should -BeFalse
    }
}

Describe 'Test-GSASegmentMatchesDestinationSpec' {
    It 'erkennt ipAddress-YAML wenn Graph ipRangeCidr/32 gespeichert hat' {
        $dest = @{ host = '192.168.178.42'; type = 'ipAddress'; ports = @('3389'); protocol = 'tcp' }
        $segment = [pscustomobject]@{
            destinationHost = '192.168.178.42/32'
            destinationType = 'ipRangeCidr'
            ports           = @('3389-3389')
            protocol        = 'tcp'
        }
        Test-GSASegmentMatchesDestinationSpec -Segment $segment -Destination $dest | Should -BeTrue
    }

    It 'erkennt ipRange-YAML wenn Graph ipRangeCidr für den Bereich gespeichert hat' {
        $dest = @{ host = '192.168.178.40-192.168.178.50'; type = 'ipRange'; ports = @('5985'); protocol = 'tcp' }
        $segment = [pscustomobject]@{
            destinationHost = '192.168.178.32/27'
            destinationType = 'ipRangeCidr'
            ports           = @('5985-5985')
            protocol        = 'tcp'
        }
        Test-GSASegmentMatchesDestinationSpec -Segment $segment -Destination $dest | Should -BeTrue
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
