BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    . (Join-Path $RepoRoot 'scripts/import/Private/ImportParsers.ps1')
}

Describe 'ConvertFrom-GSAExcelZiel' {
    It 'erkennt CIDR mit bis-Ende' {
        $r = ConvertFrom-GSAExcelZiel -Text '10.61.216.0/24 bis 10.61.216.255'
        $r.ok | Should -BeTrue
        $r.type | Should -Be 'ipRangeCidr'
        $r.host | Should -Be '10.61.216.0/24'
    }

    It 'erkennt CIDR mit Beschreibungstext' {
        $r = ConvertFrom-GSAExcelZiel -Text '10.57.10.0/24 Server Netz'
        $r.ok | Should -BeTrue
        $r.host | Should -Be '10.57.10.0/24'
    }

    It 'leitet Wildcard-IP zu /24 ab' {
        $r = ConvertFrom-GSAExcelZiel -Text '10.78.128.*'
        $r.ok | Should -BeTrue
        $r.host | Should -Be '10.78.128.0/24'
        $r.warning | Should -Not -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-GSAImportPortsString' {
    It 'parst kommagetrennte Ports' {
        ConvertFrom-GSAImportPortsString -Text '443, 4431, 6443, 21, 22, 83' |
            Should -Be @('443', '4431', '6443', '21', '22', '83')
    }

    It 'parst Port-Bereiche' {
        ConvertFrom-GSAImportPortsString -Text '5900-5905' | Should -Be @('5900-5905')
    }

    It 'kombiniert Einzelports und Bereiche' {
        ConvertFrom-GSAImportPortsString -Text '443,5900-5905' | Should -Be @('443', '5900-5905')
    }
}

Describe 'ConvertFrom-GSAExcelPortTokens' {
    It 'extrahiert Ports aus Freitext' {
        $ports = ConvertFrom-GSAExcelPortTokens -Text 'RDP 3389 und 3333 usw.'
        $ports | Should -Contain '3389'
        $ports | Should -Contain '3333'
    }

    It 'extrahiert Port-Bereiche' {
        ConvertFrom-GSAExcelPortTokens -Text '60000-60999' | Should -Be @('60000-60999')
    }

    It 'extrahiert mehrere Oracle-Ports' {
        $ports = ConvertFrom-GSAExcelPortTokens -Text 'Oracle Ports 1521, 6300'
        $ports | Should -Contain '1521'
        $ports | Should -Contain '6300'
    }
}

Describe 'Expand-GSAImportProtocols' {
    It 'expandiert both zu tcp und udp' {
        Expand-GSAImportProtocols -Protocol 'both' | Should -Be @('tcp', 'udp')
    }
}

Describe 'Resolve-GSAImportProtocolFromLegacyText' {
    It 'splittet TCP/UDP' {
        Resolve-GSAImportProtocolFromLegacyText -Text 'TCP/UDP' | Should -Be @('tcp', 'udp')
    }

    It 'nutzt tcp bei leerem Protokoll' {
        Resolve-GSAImportProtocolFromLegacyText -Text '' | Should -Be @('tcp')
    }
}

Describe 'ConvertTo-GSAApplicationNameFromImportRow' {
    It 'hängt Connector Group an Entra-Gruppennamen' {
        ConvertTo-GSAApplicationNameFromImportRow `
            -EntraGroupName 'SEC-GSA-PA-DATABASES' `
            -ConnectorGroup 'CG-EU-CENTRAL-PA-PROD-01' |
            Should -Be 'SEC-GSA-PA-DATABASES_CG_EU_CENTRAL_PA_PROD_01'
    }
}

Describe 'Merge-GSAImportedDestinations' {
    It 'dedupliziert identische Segmente' {
        $merged = @(Merge-GSAImportedDestinations -Destinations @(
            @{ host = '10.0.0.0/24'; type = 'ipRangeCidr'; ports = @('443'); protocol = 'tcp' }
            @{ host = '10.0.0.0/24'; type = 'ipRangeCidr'; ports = @('443'); protocol = 'tcp' }
        ))
        $merged.Count | Should -Be 1
    }
}
