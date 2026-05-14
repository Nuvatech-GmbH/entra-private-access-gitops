BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module (Join-Path $RepoRoot 'modules/Common/Common.psd1') -Force
    Import-Module (Join-Path $RepoRoot 'modules/PrivateAccess/PrivateAccess.psd1') -Force
}

Describe 'Invoke-GSADeployment (DryRun)' {
    It 'validiert alle YAMLs ohne Graph' {
        $apps = Join-Path $RepoRoot 'config/applications'
        { Invoke-GSADeployment -ApplicationsPath $apps -DryRun } | Should -Not -Throw
    }
}
