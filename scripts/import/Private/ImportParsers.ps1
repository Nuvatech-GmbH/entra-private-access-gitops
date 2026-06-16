function Expand-GSAImportProtocols {
    param([AllowEmptyString()][string]$Protocol)

    $p = ([string]$Protocol).Trim().ToLowerInvariant()
    switch ($p) {
        'both' { return @('tcp', 'udp') }
        'tcp' { return @('tcp') }
        'udp' { return @('udp') }
        default { return @() }
    }
}

function Resolve-GSAImportProtocolFromLegacyText {
    <#
    .SYNOPSIS
    Leitet tcp/udp aus Freitext in der Firewall-Excel ab (für Auto-Import).
    #>
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @('tcp') }

    $t = ($Text -replace '\s+', '').ToLowerInvariant()
    if ($t -match 'tcp/udp|tcp,udp|tcp&udp|tcpudp') { return @('tcp', 'udp') }
    if ($t -eq 'udp') { return @('udp') }

    if ($t -match '^(rdp|https?|ssh|smb|sql|oracle|ldap|ldaps|sftp|http)$') { return @('tcp') }

    if ($t -match 'tcp') { return @('tcp') }
    if ($t -match 'udp') { return @('udp') }

    return @('tcp')
}

function ConvertFrom-GSAExcelProtokoll {
    param([AllowEmptyString()][string]$Text)
    return @(Resolve-GSAImportProtocolFromLegacyText -Text $Text)
}

function ConvertFrom-GSAImportPortsString {
    <#
    .SYNOPSIS
    Parst ports-Spalte: kommagetrennt, Bereiche mit Bindestrich (z. B. 443,4431,5900-5905).
    #>
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $tokens = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    foreach ($part in ($Text -split '[,;]')) {
        $p = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($p)) { continue }

        if ($p -match '^(\d{1,5})(?:\s*-\s*(\d{1,5}))?$') {
            $start = [int]$Matches[1]
            $end = if ($Matches[2]) { [int]$Matches[2] } else { $start }
            if ($start -lt 1 -or $start -gt 65535 -or $end -lt 1 -or $end -gt 65535 -or $end -lt $start) {
                throw "Ungültiger Port oder Bereich in '$p'."
            }
            $norm = if ($start -eq $end) { "$start" } else { "$start-$end" }
        }
        else {
            throw "Ungültiges Port-Format in '$p' (erwartet: 443 oder 5900-5905)."
        }

        if (-not $seen.ContainsKey($norm)) {
            $seen[$norm] = $true
            $tokens.Add($norm) | Out-Null
        }
    }

    return @($tokens)
}

function ConvertFrom-GSAExcelPortTokens {
    <#
    .SYNOPSIS
    Extrahiert Port/Port-Bereiche aus freiem Excel-Text (z. B. "RDP 3389 und 3333 usw.").
    #>
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $tokens = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    foreach ($match in [regex]::Matches($Text, '\b(\d{1,5})(?:\s*-\s*(\d{1,5}))?\b')) {
        $start = [int]$match.Groups[1].Value
        $end = if ($match.Groups[2].Success) { [int]$match.Groups[2].Value } else { $start }
        if ($start -lt 1 -or $start -gt 65535 -or $end -lt 1 -or $end -gt 65535) { continue }
        if ($end -lt $start) { $tmp = $start; $start = $end; $end = $tmp }

        $token = if ($start -eq $end) { "$start" } else { "$start-$end" }
        if (-not $seen.ContainsKey($token)) {
            $seen[$token] = $true
            $tokens.Add($token) | Out-Null
        }
    }

    return @($tokens)
}

function ConvertFrom-GSAExcelZiel {
    <#
    .SYNOPSIS
    Normalisiert Ziel-Zellen aus der Firewall-Excel zu host/type.
    #>
    param([AllowEmptyString()][string]$Text)

    $result = @{
        ok      = $false
        host    = $null
        type    = $null
        warning = $null
        raw     = $Text
    }

    if ([string]::IsNullOrWhiteSpace($Text)) { return $result }

    $line = ($Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { return $result }

    # Kommentare / reine Beschreibung ohne Ziel
    if ($line -match '^(Server\s+Netz|Enterprise\s+Manager|Standard\s+Port\s+Range:?)$') {
        $result.warning = "Kein parsebares Ziel (nur Beschreibung): '$line'"
        return $result
    }

    # CIDR mit "bis …" → nur CIDR übernehmen
    if ($line -match '(?i)^(\d{1,3}(?:\.\d{1,3}){3}/\d{1,2})\s+bis\s+') {
        $result.ok = $true
        $result.host = $Matches[1]
        $result.type = 'ipRangeCidr'
        return $result
    }

    # CIDR mit angehängtem Text (z. B. "10.57.10.0/24 Server Netz")
    if ($line -match '(?i)^(\d{1,3}(?:\.\d{1,3}){3}/\d{1,2})\b') {
        $result.ok = $true
        $result.host = $Matches[1]
        $result.type = 'ipRangeCidr'
        if ($line -notmatch '^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$') {
            $result.warning = "Zusatztext im Ziel ignoriert: '$line'"
        }
        return $result
    }

    # IP-Bereich Start-Ende
    if ($line -match '(?i)^(\d{1,3}(?:\.\d{1,3}){3})\s*-\s*(\d{1,3}(?:\.\d{1,3}){3})$') {
        $result.ok = $true
        $result.host = "$($Matches[1])-$($Matches[2])"
        $result.type = 'ipRange'
        return $result
    }

    # Wildcard-IP → heuristisch /24 (manuell prüfen)
    if ($line -match '(?i)^(\d{1,3}(?:\.\d{1,3}){2})\.\*$') {
        $result.ok = $true
        $result.host = "$($Matches[1]).0/24"
        $result.type = 'ipRangeCidr'
        $result.warning = "Wildcard '$line' als $($result.host) abgeleitet – bitte manuell prüfen."
        return $result
    }

    # Einzel-IP
    if ($line -match '^(?i)(\d{1,3}(?:\.\d{1,3}){3})$') {
        $result.ok = $true
        $result.host = $Matches[1]
        $result.type = 'ipAddress'
        return $result
    }

    # FQDN (einfache Heuristik)
    if ($line -match '(?i)^([a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?)+)$') {
        $result.ok = $true
        $result.host = $Matches[1].ToLowerInvariant()
        $result.type = 'fqdn'
        return $result
    }

    $result.warning = "Ziel nicht erkannt: '$line'"
    return $result
}

function Get-GSAImportedDestinationSignature {
    param(
        [string]$HostValue,
        [string]$TypeValue,
        [string]$Protocol,
        [string[]]$Ports
    )

    $portsNorm = (@($Ports) | Sort-Object) -join ','
    return ("$HostValue|$TypeValue|$Protocol|$portsNorm").ToLowerInvariant()
}

function Merge-GSAImportedDestinations {
    param([Parameter(Mandatory)][object[]]$Destinations)

    $merged = @{}
    foreach ($d in $Destinations) {
        if ($null -eq $d) { continue }
        $sig = Get-GSAImportedDestinationSignature -HostValue $d.host -TypeValue $d.type -Protocol $d.protocol -Ports @($d.ports)
        if ($merged.ContainsKey($sig)) { continue }
        $merged[$sig] = $d
    }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $merged.GetEnumerator()) {
        $result.Add($entry.Value) | Out-Null
    }
    return $result.ToArray()
}

function ConvertTo-GSAImportConnectorSlug {
    param([Parameter(Mandatory)][string]$ConnectorGroup)

    $slug = ($ConnectorGroup -replace '[^A-Za-z0-9]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Connector Group '$ConnectorGroup' ergibt keinen gültigen Namensbestandteil."
    }
    return $slug
}

function ConvertTo-GSAApplicationNameFromImportRow {
    <#
    .SYNOPSIS
    Erzeugt metadata.name: Entra-Gruppenname (EIT_PA_Admin_…) + Connector Group.
    Eine App = admin_rolle + connector_group (über entra_group_name und connector_group).
    #>
    param(
        [Parameter(Mandatory)][string]$EntraGroupName,
        [Parameter(Mandatory)][string]$ConnectorGroup
    )

    $base = $EntraGroupName.Trim().TrimEnd('_')
    $connectorSlug = ConvertTo-GSAImportConnectorSlug -ConnectorGroup $ConnectorGroup
    $name = "${base}_${connectorSlug}" -replace '_{2,}', '_'
    if ($name.Length -gt 120) {
        $name = $name.Substring(0, 120).TrimEnd('_')
    }
    return $name
}

function ConvertTo-GSAImportedApplicationName {
    <#
    .SYNOPSIS
    Legacy-Hilfsfunktion für ältere Import-Pfade (Roh-Excel mit Einheit/Nr.).
    #>
    param(
        [Parameter(Mandatory)][string]$AdminRolle,
        [string]$Einheit,
        [string]$Nr
    )

    $parts = @('PA')
    $parts += (($AdminRolle -replace '[^A-Za-z0-9]+', '-') -split '-' | Where-Object { $_ } | ForEach-Object { $_.Substring(0, [Math]::Min($_.Length, 12)).ToUpperInvariant() })
    if (-not [string]::IsNullOrWhiteSpace($Einheit)) {
        $parts += (($Einheit -replace '[^A-Za-z0-9]+', '-').ToUpperInvariant())
    }
    if (-not [string]::IsNullOrWhiteSpace($Nr)) {
        $parts += ([string]$Nr).PadLeft(3, '0')
    }

    $name = ($parts -join '-') -replace '-{2,}', '-'
    if ($name.Length -gt 120) { $name = $name.Substring(0, 120).TrimEnd('-') }
    return $name
}

function ConvertTo-GSAImportedFileName {
    param([Parameter(Mandatory)][string]$ApplicationName)

    $slug = ($ApplicationName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    return "pa-$slug.yaml"
}

function Resolve-GSAImportMappingValue {
    param(
        [Parameter(Mandatory)][hashtable]$Map,
        [Parameter(Mandatory)][string]$Key,
        [string]$Fallback = $null
    )

    if ($Map.ContainsKey($Key)) { return [string]$Map[$Key] }
    if ($null -ne $Fallback) { return $Fallback }
    return $null
}
