function Test-GSAConfiguration {
    <#
    .SYNOPSIS
    Validiert eine einzelne YAML-Datei gegen das JSON Schema (optional).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$SchemaPath,
        [switch]$SkipSchema
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "Datei nicht gefunden: $Path" }

    $doc = ConvertFrom-GSAYamlDocument -Path $Path
    if (-not $doc.apiVersion -or $doc.apiVersion -ne 'gsa.gitops/v1') {
        throw "Ungültige apiVersion in $Path"
    }
    if (-not $doc.kind -or $doc.kind -ne 'PrivateAccessApplication') {
        throw "Ungültiger kind in $Path"
    }

    if (-not $SkipSchema) {
        if (-not $SchemaPath) {
            # Public -> PrivateAccess -> modules -> Repository-Root
            $repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
            $SchemaPath = Join-Path $repoRoot 'schemas/private-access-application.schema.json'
        }
        if (-not (Test-Path -LiteralPath $SchemaPath)) {
            throw "Schema nicht gefunden: $SchemaPath"
        }

        $json = $doc | ConvertTo-Json -Depth 50
        $json | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop | Out-Null
    }

    return $true
}
