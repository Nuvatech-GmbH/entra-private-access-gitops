using namespace System.Collections.Generic

function New-GSACorrelationId {
    <#
    .SYNOPSIS
    Erzeugt eine neue Korrelations-ID für strukturierte Logs und Deployment-Traces.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    process {
        return [guid]::NewGuid().ToString('n')
    }
}

function Get-GSAEnvBool {
    <#
    .SYNOPSIS
    Liest eine Umgebungsvariable als booleschen Wert (true/false/1/0).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$Default = $false
    )
    $raw = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
    switch -Regex ($raw.Trim().ToLowerInvariant()) {
        '^(1|true|yes|y)$' { return $true }
        '^(0|false|no|n)$' { return $false }
        default { return $Default }
    }
}

function Write-GSAStructuredLog {
    <#
    .SYNOPSIS
    Schreibt ein strukturiertes Logereignis als JSON-Zeile (stdout) plus optional farbige Konsolenzeile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Trace','Debug','Information','Warning','Error','Critical')][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$CorrelationId,
        [hashtable]$Data = @{}
    )

    $ts = [DateTimeOffset]::UtcNow.ToString('o')
    $entry = [ordered]@{
        timestamp      = $ts
        level          = $Level
        message        = $Message
        correlationId  = $CorrelationId
        machineName    = [Environment]::MachineName
        processId      = $PID
        data           = $Data
    }

    $json = ($entry | ConvertTo-Json -Compress -Depth 10)
    Write-Output $json

    if (-not (Get-GSAEnvBool -Name 'GSA_LOG_DISABLE_COLOR' -Default $false)) {
        $prefix = "[$ts][$Level]"
        if ($CorrelationId) { $prefix += "[$CorrelationId]" }
        Write-Information "$prefix $Message" -InformationAction Continue
    }
}

function Invoke-GSARetryableOperation {
    <#
    .SYNOPSIS
    Führt eine Operation mit exponentiellem Backoff und Jitter aus.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [int]$MaxAttempts = 5,
        [int]$InitialBackoffMs = 250,
        [int]$MaxBackoffMs = 8000,
        [scriptblock]$ShouldRetry = {
            param($ErrorRecord)
            $msg = $ErrorRecord.Exception.Message
            if ($msg -match '429|503|504|timeout|Too Many Requests') { return $true }
            return $false
        }
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return (& $Action)
        }
        catch {
            $retry = $false
            try { $retry = (& $ShouldRetry $_) } catch { $retry = $false }

            if (-not $retry -or $attempt -ge $MaxAttempts) {
                throw
            }

            $base = [Math]::Min($MaxBackoffMs, $InitialBackoffMs * [Math]::Pow(2, ($attempt - 1)))
            $jitter = Get-Random -Minimum 0 -Maximum ([int]($base * 0.25) + 1)
            $sleep = [int]([Math]::Min($MaxBackoffMs, $base + $jitter))
            Write-GSAStructuredLog -Level 'Warning' -Message "Transient failure; retrying attempt $attempt/$MaxAttempts after ${sleep}ms" -Data @{ error = $_.Exception.Message }
            Start-Sleep -Milliseconds $sleep
        }
    }
}

Export-ModuleMember -Function @(
    'New-GSACorrelationId',
    'Write-GSAStructuredLog',
    'Invoke-GSARetryableOperation',
    'Get-GSAEnvBool'
)
