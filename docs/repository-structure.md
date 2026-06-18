# Repository-Struktur (Verzeichnis-Erklärung)

Dieses Repository folgt einem **Platform-Engineering**-Layout: klare Trennung zwischen Desired State (`config`), ausführbarem Code (`modules`, `scripts`), Qualitätssicherung (`tests`, `schemas`) und Betriebsdokumentation (`docs`).

| Pfad | Zweck |
| --- | --- |
| `/.github` | CI/CD-Workflows, PR-Vorlagen, CODEOWNERS. Enthält die **GitOps-Gates** (Validierung, WhatIf, Produktions-Deployment). |
| `/.github/workflows` | `validation.yml` (wiederverwendbare Basisprüfungen), `pull-request-validation.yml` (PR), `deploy-production.yml` (Merge → Produktion). |
| `/build` | Hilfsskripte für lokale CI (`Invoke-LocalCI.ps1`) und spätere Erweiterungen (Packaging, Releases). |
| `/config/applications` | **Single Source of Truth** für produktive Private-Access-Anwendungen (eine YAML-Datei pro App). |
| `/config/examples` | YAML-Vorlagen und Demos (`*.example.yaml`) – werden **nicht** deployed. |
| `/docs` | Architektur, Governance, Security, Onboarding, Betrieb, FAQ, Roadmap. |
| `/docs/architecture` | Zielbild, Komponenten, Datenflüsse, Erweiterbarkeit. |
| `/docs/governance` | Review-Modell, Ownership, Notfallprozesse, CAB-Anbindung. |
| `/docs/security` | OIDC, Least Privilege, Mandantenföderation, Auditing. |
| `/docs/onboarding` | Einstieg für neue Engineer:innen (erster PR, lokale Checks). |
| `/docs/troubleshooting` | Typische Fehlerbilder (Graph, Connector Groups, YAML). |
| `/docs/examples` | Narrative Beispiele (wie ein Change aussehen soll). |
| `/docs/operations` | Runbooks (Deployment, Rollback, Monitoring-Konzepte). |
| `/modules/Common` | Querschnitt: strukturierte Logs, Retries, Korrelation. |
| `/modules/PrivateAccess` | Domänenlogik: Graph-Zugriff, Reconciliation, Cmdlets (`Connect-GSAEnvironment`, `Invoke-GSADeployment`, …). |
| `/schemas` | JSON Schema für `gsa.gitops/v1` Dokumente (CI-Validierung). |
| `/scripts/deploy` | Entry Points für produktive Deployments (GitHub Actions & Break-Glass). |
| `/scripts/validate` | Repository-weite Validierung (Schema, Naming, Duplikate). |
| `/import` | Massenimport: Arbeitsbuch-Vorlage, Mappings, lokale Quelldaten (`import/excel/`, nicht im Repo). |
| `/import/templates` | CSV-Arbeitsbuch-Vorlage für Excel/CSV-Import. |
| `/scripts/import` | Validierung und Konvertierung Import → YAML. |
| `/tests/unit` | Pester Unit-Tests (schnell, deterministisch). |
| `/tests/integration` | Manuelle / halbautomatische Integration gegen einen Mandanten (Struktur + Anleitung). |

Weitere Dateien im Root:

- `README.md` – Einstieg und Gesamtüberblick.
- `CONTRIBUTING.md` – Branching, Reviews, Qualitätsanforderungen.
- `SECURITY.md` – Meldung von Sicherheitsvorfällen.
- `CHANGELOG.md` – Versionsnotizen (Release-Disziplin).
- `PSScriptAnalyzerSettings.psd1` – konsistente PowerShell-Qualitätsregeln.
