BeforeAll {
    Import-Module "$PSScriptRoot/../../modules/Common/Common.psd1" -Force
}

Describe 'Common Modul' {
    It 'erzeugt Korrelations-IDs' {
        $a = New-GSACorrelationId
        $b = New-GSACorrelationId
        $a | Should -Not -Be $b
    }

    It 'liest boolesche Umgebungsvariablen' {
        $env:GSA_TEST_FLAG = '1'
        Get-GSAEnvBool -Name 'GSA_TEST_FLAG' -Default $false | Should -Be $true
        Remove-Item Env:GSA_TEST_FLAG
    }
}
