# Onboarding: Neue Engineer:innen

## Voraussetzungen

- PowerShell 7 (`pwsh`)
- Azure CLI (`az`) für lokale Token-Tests optional
- Git
- Mitgliedschaft in den GitHub Teams aus `CODEOWNERS`

## Lokale Validierung

```powershell
cd <repo>
pwsh ./build/Invoke-LocalCI.ps1
```

Das Skript installiert benötigte Module in den CurrentUser-Scope und führt Analyzer, YAML/Schema-Validierung und Pester aus.

## Neue Anwendung hinzufügen

1. Kopieren Sie eine Beispieldatei aus `config/applications/*.example.yaml`.
2. Entfernen Sie `.example` aus dem Dateinamen (empfohlen: Dateiname = `metadata.name` in Kleinbuchstaben mit Bindestrichen).
3. Setzen Sie realistische Werte:
   - `metadata.name` eindeutig (`PA-<TEAM>-<SYSTEM>`)
   - `spec.connectorGroup` exakt wie im Mandanten
   - `spec.destinations` minimal halten (Least Privilege Ports)
   - `spec.assignments` bevorzugt mit `principalId` (deterministisch)
4. Öffnen Sie einen PR → Pipeline validiert automatisch.

## Bestehende Anwendung ändern

- Kleine Änderungen (Tags, Beschreibung): Standard-Review.
- Änderungen an Segmenten oder Zuweisungen: erhöhtes Risiko → Security Review laut interner Policy.

## Wo finde ich Hilfe?

- `docs/troubleshooting/common-issues.md`
- `docs/examples/sample-change.md`
