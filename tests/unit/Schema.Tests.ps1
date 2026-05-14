BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module (Join-Path $RepoRoot 'modules/Common/Common.psd1') -Force
    Import-Module (Join-Path $RepoRoot 'modules/PrivateAccess/PrivateAccess.psd1') -Force
}

Describe 'YAML Schema Validierung' {
    It 'validiert Beispiel HR Portal' {
        $path = Join-Path $RepoRoot 'config/applications/contoso-hr-portal.example.yaml'
        { Test-GSAConfiguration -Path $path } | Should -Not -Throw
    }

    It 'validiert Beispiel Fileserver' {
        $path = Join-Path $RepoRoot 'config/applications/contoso-fileserver.example.yaml'
        { Test-GSAConfiguration -Path $path } | Should -Not -Throw
    }
}
