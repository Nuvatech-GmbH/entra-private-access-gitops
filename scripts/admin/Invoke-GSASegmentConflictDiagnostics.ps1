<#
.SYNOPSIS
    Hilft bei Invalid_AppSegments_NonwebApp_Duplicate: findet Konflikt-Apps/Segmente per Graph (auch soft-deleted).

.DESCRIPTION
    Die GSA/Private-Access-Backend-Ebene behält Application Segments oft noch,
    nachdem Enterprise Apps im Portal gelöscht wurden. Die Konflikt-appId erscheint
    dann nicht mehr in der UI, blockiert aber neue Segmente mandantenweit.

.PARAMETER ConflictObjectId
    objectId aus der Graph-Fehlermeldung (conflictingApplication).

.PARAMETER ConflictAppId
    appId aus der Graph-Fehlermeldung.

.PARAMETER ListAllSegments
    Listet Segmente aller Apps mit onPremisesPublishing (kann dauern).

.PARAMETER RemoveSegmentsOnConflictApp
    Löscht alle Segmente auf der gefundenen Konflikt-Application (nach Bestätigung).

.EXAMPLE
    ./Invoke-GSASegmentConflictDiagnostics.ps1 -ConflictObjectId f8473034-5426-4d77-912c-7c323b8ec6dd -ConflictAppId 84ba0dce-1e90-45a6-87a8-6f2020d3b918
#>
[CmdletBinding()]
param(
    [string]$ConflictObjectId,
    [string]$ConflictAppId,
    [switch]$ListAllSegments,
    [switch]$RemoveSegmentsOnConflictApp
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
Import-Module (Join-Path $repoRoot 'modules/Common/Common.psm1') -Force
Import-Module (Join-Path $repoRoot 'modules/PrivateAccess/PrivateAccess.psm1') -Force

if (-not (Get-MgContext)) {
    throw 'Bitte zuerst anmelden, z. B.: Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All","Application.ReadWrite.All"'
}

function Invoke-GSADiagGraph {
    param([string]$Method, [string]$Uri)
    return Invoke-MgGraphRequest -Method $Method -Uri $Uri -ErrorAction Stop
}

function Get-GSADiagApplicationSegments {
    param([string]$ApplicationObjectId)
    $uri = "https://graph.microsoft.com/beta/applications/$ApplicationObjectId/onPremisesPublishing/segmentsConfiguration/microsoft.graph.ipSegmentConfiguration/applicationSegments"
    try {
        $r = Invoke-GSADiagGraph -Method GET -Uri $uri
        return @($r.value)
    }
    catch {
        Write-Warning "Segmente nicht lesbar für Application $ApplicationObjectId : $($_.Exception.Message)"
        return @()
    }
}

Write-Host "`n=== GSA Segment-Konflikt Diagnose ===`n" -ForegroundColor Cyan

if ($ConflictObjectId -or $ConflictAppId) {
    Write-Host "--- Konflikt-Referenz aus Fehlermeldung ---" -ForegroundColor Yellow
    if ($ConflictObjectId) { Write-Host "objectId: $ConflictObjectId" }
    if ($ConflictAppId) { Write-Host "appId:    $ConflictAppId" }

    $app = $null
    if ($ConflictObjectId) {
        try {
            $app = Invoke-GSADiagGraph -Method GET -Uri "https://graph.microsoft.com/beta/applications/$ConflictObjectId"
            Write-Host "`n[OK] Application (beta) existiert noch: displayName=$($app.displayName)" -ForegroundColor Green
        }
        catch {
            Write-Host "`n[INFO] Application objectId nicht als aktive App lesbar (evtl. gelöscht)." -ForegroundColor DarkYellow
        }
    }

    if (-not $app -and $ConflictAppId) {
        $filter = [uri]::EscapeDataString("appId eq '$ConflictAppId'")
        $search = Invoke-GSADiagGraph -Method GET -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=$filter&`$select=id,displayName,appId,deletedDateTime"
        if ($search.value -and $search.value.Count -gt 0) {
            $app = $search.value[0]
            Write-Host "[OK] Application per appId gefunden: $($app.displayName) id=$($app.id)" -ForegroundColor Green
            $ConflictObjectId = [string]$app.id
        }
    }

    if ($ConflictAppId) {
        $spFilter = [uri]::EscapeDataString("appId eq '$ConflictAppId'")
        $sps = Invoke-GSADiagGraph -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$spFilter&`$select=id,displayName,appId"
        if ($sps.value -and $sps.value.Count -gt 0) {
            Write-Host "[OK] Service Principal sichtbar: $($sps.value[0].displayName) spId=$($sps.value[0].id)" -ForegroundColor Green
        }
        else {
            Write-Host "[INFO] Kein Service Principal mit dieser appId (App oft vollständig entfernt)." -ForegroundColor DarkYellow
        }
    }

    Write-Host "`n--- Papierkorb (soft-deleted Applications) ---" -ForegroundColor Yellow
    try {
        $deleted = Invoke-GSADiagGraph -Method GET -Uri 'https://graph.microsoft.com/v1.0/directory/deletedItems/microsoft.graph.application'
        $match = @($deleted.value) | Where-Object {
            ($ConflictObjectId -and $_.id -eq $ConflictObjectId) -or
            ($ConflictAppId -and $_.appId -eq $ConflictAppId)
        }
        if ($match.Count -gt 0) {
            foreach ($d in $match) {
                Write-Host "[GEFUNDEN] Soft-deleted: displayName=$($d.displayName) id=$($d.id) appId=$($d.appId) deleted=$($d.deletedDateTime)" -ForegroundColor Magenta
                Write-Host "  → Entra: App registrations → Deleted applications → endgültig löschen (Purge)"
            }
        }
        else {
            Write-Host "Kein Treffer im deletedItems-Application-Papierkorb (Segment kann trotzdem in GSA-Backend verwaist sein)." -ForegroundColor DarkYellow
        }
    }
    catch {
        Write-Warning "deletedItems nicht lesbar (fehlende Directory.Read.All?): $($_.Exception.Message)"
    }

    if ($ConflictObjectId) {
        Write-Host "`n--- Application Segments (GSA-Backend via Graph) ---" -ForegroundColor Yellow
        $segments = Get-GSADiagApplicationSegments -ApplicationObjectId $ConflictObjectId
        if ($segments.Count -eq 0) {
            Write-Host "Keine Segmente per Graph auf dieser ApplicationId – Backend kann dennoch verwaiste Einträge halten." -ForegroundColor DarkYellow
            Write-Host "Nächste Schritte: Entra PowerShell Beta (Remove-EntraBetaPrivateAccessApplicationSegment) oder Microsoft Support." -ForegroundColor DarkYellow
        }
        else {
            foreach ($s in $segments) {
                Write-Host "  Segment id=$($s.id) host=$($s.destinationHost) type=$($s.destinationType) ports=$($s.ports -join ',') protocol=$($s.protocol)"
            }
            if ($RemoveSegmentsOnConflictApp) {
                if ($PSCmdlet.ShouldProcess($ConflictObjectId, 'Alle Application Segments löschen')) {
                    foreach ($s in $segments) {
                        $delUri = "https://graph.microsoft.com/beta/applications/$ConflictObjectId/onPremisesPublishing/segmentsConfiguration/microsoft.graph.ipSegmentConfiguration/applicationSegments/$($s.id)"
                        Invoke-GSADiagGraph -Method DELETE -Uri $delUri
                        Write-Host "  Gelöscht: $($s.id)" -ForegroundColor Green
                    }
                }
            }
            else {
                Write-Host "`nZum Löschen: -RemoveSegmentsOnConflictApp (erfordert Application.ReadWrite.All)" -ForegroundColor Cyan
            }
        }
    }
}

if ($ListAllSegments) {
    Write-Host "`n--- Alle Applications mit Publishing (Auszug) ---" -ForegroundColor Yellow
    $filter = [uri]::EscapeDataString("tags/any(t:t eq 'WindowsAzureActiveDirectoryIntegratedApp')")
    # Breiter: alle Apps mit onPremisesPublishing – paginiert vereinfacht
    $uri = 'https://graph.microsoft.com/beta/applications?$select=id,displayName,appId&$top=999'
    $page = Invoke-GSADiagGraph -Method GET -Uri $uri
    $candidates = @($page.value) | Where-Object { $_.displayName -like 'PA-*' -or $_.displayName -match '^[0-9a-f-]{36}$' }
    foreach ($a in $candidates) {
        $segs = Get-GSADiagApplicationSegments -ApplicationObjectId $a.id
        if ($segs.Count -gt 0) {
            Write-Host "`n$($a.displayName) ($($a.id)) appId=$($a.appId)"
            foreach ($s in $segs) {
                Write-Host "  -> $($s.destinationHost) $($s.destinationType) $($s.ports -join ',') $($s.protocol)"
            }
        }
    }
}

Write-Host @"

=== Hinweise ===
• Konflikt-App im Portal oft NICHT sichtbar, weil displayName = appId (GUID) oder App nur in GSA-Backend existiert.
• Suche: Unternehmensanwendungen → nach Objekt-ID (objectId), NICHT nur nach Anzeigename.
• Oder: Global Secure Access → Applications → Enterprise applications (nicht Entra → Enterprise Apps allein).
• Löschen im Entra-Portal entfernt Segmente NICHT zuverlässig → Segmente per Graph/PowerShell löschen oder Garbage Collection abwarten (kann Tage dauern).
• Papierkorb: App-Registrierungen → Gelöschte Anwendungen → Purge (manuell; Pipeline macht das nicht) → docs/operations/application-lifecycle-and-purge.md
• Doku: docs/troubleshooting/common-issues.md (Verwaiste Segmente)

"@ -ForegroundColor Cyan
