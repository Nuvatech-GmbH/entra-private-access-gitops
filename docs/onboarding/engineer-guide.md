# Onboarding: Neue Engineer:innen

> **Einstieg ohne Git-Vorkenntnisse:** Schritt-für-Schritt-Anleitung (Browser, PR, Pipeline) im [README – Neue Private-Access-Regel](../README.md#neue-private-access-regel-anlegen--schritt-für-schritt).

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

1. Kopieren Sie eine Beispieldatei aus `config/applications/*.example.yaml` (**`.example.yaml` wird nie deployed**).
2. Speichern Sie als neue Datei **ohne** `.example` (z. B. `pa-team-system.yaml`).
3. Setzen Sie realistische Werte:
   - `metadata.name` eindeutig (`PA-<TEAM>-<SYSTEM>`)
   - `spec.connectorGroup` exakt wie im Mandanten
   - `spec.destinations` minimal halten (Least Privilege Ports)
   - `spec.assignments` bevorzugt mit `principalId` (deterministisch)
4. Öffnen Sie einen PR → Pipeline validiert automatisch.

## Bestehende Anwendung ändern

- Kleine Änderungen (Tags, Beschreibung): Standard-Review.
- Änderungen an Segmenten oder Zuweisungen: erhöhtes Risiko → Security Review laut interner Policy.

## Nach dem ersten erfolgreichen Deploy (Portal)

Die Pipeline ersetzt **nicht** die mandantenweite GSA-Konfiguration. Vor dem ersten Nutzertest mit Plattform/Identity abgleichen:

1. **Datenverkehrsprofil für privaten Zugriff** aktivieren (Global Secure Access → Verbinden → Datenverkehrsweiterleitung).
2. **Gruppe** aus `spec.assignments` auch diesem Profil zuweisen (zusätzlich zur Zuweisung an die Enterprise App).
3. Auf Testgeräten den **Global Secure Access Client** installieren, wenn `isAccessibleViaZTNAClient: true`.

Ausführliche Checkliste, Symptomtabelle und Abgrenzung GitOps vs. Portal:  
[`docs/operations/portal-configuration-after-deploy.md`](../operations/portal-configuration-after-deploy.md)

## Wo finde ich Hilfe?

- `docs/operations/portal-configuration-after-deploy.md` (Profil, Client, End-to-End-Test)
- `docs/troubleshooting/common-issues.md`
- `docs/examples/sample-change.md`
