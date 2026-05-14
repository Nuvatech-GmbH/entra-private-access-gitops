# Microsoft Entra Private Access – Enterprise GitOps

Dieses Repository ist die **Single Source of Truth** für **Microsoft Entra Private Access** (Global Secure Access / Zero Trust Network Access) Anwendungen in **einem** produktiven Microsoft Entra Mandanten. Es kombiniert **deklarative YAML-Konfiguration**, **PowerShell 7 Automatisierung** über **Microsoft Graph** und **GitHub Actions** mit **OIDC**, um Änderungen **governed**, **auditierbar** und **idempotent** auszurollen.

> Graph-Hinweis: Die Automatisierung folgt dem offiziellen Microsoft Learn Tutorial inklusive `beta` Endpunkten für Segmente und Connector Groups. Referenz: [Configure Microsoft Entra Private Access using Microsoft Graph APIs](https://learn.microsoft.com/en-us/graph/tutorial-entra-private-access)

---

## Inhaltsverzeichnis

1. [Warum dieses Repository existiert](#warum-dieses-repository-existiert)
2. [Architektur (Zielbild)](#architektur-zielbild)
3. [End-to-End Deployment Flow](#end-to-end-deployment-flow)
4. [Repository-Struktur](#repository-struktur)
5. [YAML Desired State (`gsa.gitops/v1`)](#yaml-desired-state-gsagitopsv1)
6. [PowerShell Module](#powershell-module)
7. [GitHub Actions & OIDC](#github-actions--oidc)
8. [Validierung, WhatIf und Drift](#validierung-whatif-und-drift)
9. [Genehmigungen & Branch Protection](#genehmigungen--branch-protection)
10. [Rollback & Emergency](#rollback--emergency)
11. [Sicherheit & Least Privilege](#sicherheit--least-privilege)
12. [Observability](#observability)
13. [Lokale Entwicklung](#lokale-entwicklung)
14. [Weiterführende Dokumentation](#weiterführende-dokumentation)

---

## Warum dieses Repository existiert

In großen Organisationen skaliert Private Access nicht über „ClickOps“, sondern über:

- **Git als System of Record** (Reviews, Blame, Tags, Releases)
- **Automatisierte Gates** vor jeder Mutation im Mandanten
- **klare Ownership** pro Anwendung (`metadata.owners`)
- **Nachvollziehbarkeit** über Tickets (`metadata.changeReference`) und Pipeline-Artefakte

Dieses Repository ist bewusst **ohne** künstliche Dev/Test/Prod-Mandanten im Git modelliert. Stattdessen gibt es **einen** produktiven Zielmandanten und **mehrstufige Sicherheit** (Validierung, WhatIf/Drift, Reviews, Environment Protection).

---

## Architektur (Zielbild)

```mermaid
flowchart LR
  Eng[Engineer:innen] -->|PR| GitHub[GitHub: YAML + Reviews]
  GitHub -->|validation.yml| Val[Schema + Governance + Pester]
  GitHub -->|pull-request-validation| WhatIf[Graph Read: Drift Report]
  GitHub -->|merge main| Dep[deploy-production.yml]
  Dep -->|OIDC| EntraId[Microsoft Entra App Registration]
  EntraId -->|Microsoft Graph| Tenant[(Produktiver Entra Tenant)]
  Tenant -->|Audit Logs| SOC[SOC / Monitoring]
```

### Schichtenmodul

```mermaid
flowchart TB
  YAML[config/applications/*.yaml] --> ValS[JSON Schema + Invoke-GSAValidation.ps1]
  ValS --> PS[modules/PrivateAccess]
  PS --> GC[Private/GraphClient.ps1]
  GC --> MG[Microsoft.Graph.Authentication\nInvoke-MgGraphRequest]
  MG --> API[(Graph beta/v1)]
```

Details: `docs/architecture/overview.md`

---

## End-to-End Deployment Flow

```mermaid
sequenceDiagram
  participant Dev as Engineer
  participant GH as GitHub PR
  participant CI as PR Pipeline
  participant Main as main Branch
  participant Prod as Environment production
  participant Entra as Microsoft Entra

  Dev->>GH: YAML ändern + PR
  GH->>CI: Schema/Naming/Duplikate/Pester
  CI->>Entra: Optional Drift/WhatIf (Read)
  Dev->>GH: Review + Merge
  Main->>Prod: deploy-production.yml
  Prod->>Entra: Idempotent reconcile (Write)
```

---

## Repository-Struktur

Die vollständige Erklärung aller Ordner finden Sie in `docs/repository-structure.md` (Tabelle inkl. Zweck von `modules`, `scripts`, `schemas`, `tests`, `docs`, `build`, `.github`).

---

## YAML Desired State (`gsa.gitops/v1`)

Jede Datei unter `config/applications/` beschreibt **genau eine** Anwendung.

Kernelemente:

- `metadata.name` – entspricht dem `displayName` der erzeugten App (eindeutig).
- `metadata.owners` – Verantwortliche (E-Mail).
- `metadata.changeReference` – externes Ticket / RFC / CHG.
- `metadata.graphApplicationId` – optional, für Importe und stabile Bindung.
- `spec.applicationType` – `enterprise` (nonwebapp) oder `quickAccess` (quickaccessapp).
- `spec.connectorGroup` – **Name** der Application Proxy Connector Group (wird per Graph aufgelöst).
- `spec.destinations` – Liste aus Zielen mit `host`, `type`, `ports`, `protocol`.
- `spec.assignments` – `principalId` (empfohlen) oder `principalName` (nur User/Group, Auflösung zur Laufzeit).

Beispiele: `config/applications/contoso-hr-portal.example.yaml`, `config/applications/contoso-fileserver.example.yaml`.

JSON Schema: `schemas/private-access-application.schema.json`

---

## PowerShell Module

### `modules/Common`

Strukturierte Logs (`Write-GSAStructuredLog`), Korrelation (`New-GSACorrelationId`), Retry (`Invoke-GSARetryableOperation`).

### `modules/PrivateAccess`

Öffentliche Cmdlets (Auswahl):

| Cmdlet | Zweck |
| --- | --- |
| `Connect-GSAEnvironment` | Graph Session (Azure CLI Token nach OIDC, interaktiv, optional AccessToken) |
| `Get-GSAPrivateAccessApplication` | Lookup per `graphApplicationId` oder `displayName` |
| `New-GSAPrivateAccessApplication` | Erstellt App via Template + Segmente + Zuweisungen |
| `Set-GSAPrivateAccessApplication` | Idempotentes Update (optional entfernen abwesender Segmente/Zuweisungen) |
| `Remove-GSAPrivateAccessApplication` | Löscht Application (Break-Glass) |
| `Compare-GSAState` | Drift zwischen YAML und Mandant |
| `Test-GSAConfiguration` | Schema-Check einer Datei |
| `Invoke-GSADeployment` | Ordner-basiertes Deployment mit `-DryRun` / `-WhatIf` |

> **Microsoft Entra PowerShell** kann ergänzend für Directory-Szenarien genutzt werden; die Kernpfade sind absichtlich **Microsoft Graph**-basiert, um API-Stabilität und Portabilität zu maximieren.

---

## GitHub Actions & OIDC

| Workflow | Trigger | Zweck |
| --- | --- | --- |
| `validation.yml` | `workflow_call`, `workflow_dispatch` | PSScriptAnalyzer, YAML/Schema, Pester, Artefakte |
| `pull-request-validation.yml` | PR zu `main` | Ruft `validation.yml` auf + optional Drift/WhatIf + PR-Kommentar |
| `deploy-production.yml` | Push `main` (Pfade gefiltert) | Produktives Reconcile nach Environment-Genehmigung |

### Konfiguration in GitHub

Repository Variables (Beispiel):

- `AZURE_TENANT_ID`
- `GSA_GRAPH_CLIENT_ID` (App Registration der Pipeline)

GitHub Environment:

- `production` mit **Required reviewers** und optional **Wait timer**

Microsoft Entra:

- Federated Credential für GitHub OIDC passend zu eurer Branch/Environment-Strategie

Details: `docs/security/authentication-and-permissions.md`

---

## Validierung, WhatIf und Drift

- **PR Phase (ohne Writes)**: `scripts/validate/Invoke-GSAValidation.ps1` prüft Schema, Naming (`PA-...`), Duplikate auf Ziel-Signatur-Ebene und Assignment-Plausibilität.
- **WhatIf / Drift**: `scripts/utils/Export-GSAWhatIfReport.ps1` erzeugt JSON mit `Compare-GSAState` Ergebnissen (Graph Reads).
- **Merge / Prod**: `scripts/deploy/Invoke-ProductionDeployment.ps1` führt `Invoke-GSADeployment` aus.

---

## Genehmigungen & Branch Protection

Empfohlene Kombination:

- Branch Protection auf `main` (PR required, Status Checks required)
- `CODEOWNERS` für `config/applications/**`
- GitHub Environment `production` als operative Freigabe **zusätzlich** zum Code Review

Governance-Modell: `docs/governance/model.md`

---

## Rollback & Emergency

- **Standard**: Git Revert + erneutes Deployment (Git bleibt Source of Truth).
- **Emergency**: siehe `docs/operations/runbook.md` (Break-Glass, Drift-Bereinigung).

---

## Sicherheit & Least Privilege

- Keine Secrets im Repository.
- OIDC statt Client Secrets.
- App Permissions minimal halten (siehe Tabelle in `docs/security/authentication-and-permissions.md`).

---

## Observability

- JSON Logs mit `correlationId` pro Lauf.
- GitHub Step Summary in `Invoke-ProductionDeployment.ps1` (Tabelle pro Datei).
- Konzept für Log Analytics / Sentinel: `docs/architecture/overview.md` und `docs/operations/runbook.md`.

---

## Lokale Entwicklung

```powershell
git clone <repo>
cd entra-private-access-gitops
pwsh ./build/Invoke-LocalCI.ps1
```

Das Skript installiert u. a. `powershell-yaml`, `Pester`, `PSScriptAnalyzer`, `Microsoft.Graph.Authentication` in den CurrentUser-Scope.

---

## Weiterführende Dokumentation

| Thema | Datei |
| --- | --- |
| Ordner & Zweck | `docs/repository-structure.md` |
| Architektur | `docs/architecture/overview.md` |
| Governance | `docs/governance/model.md` |
| Security / Graph Permissions | `docs/security/authentication-and-permissions.md` |
| Onboarding | `docs/onboarding/engineer-guide.md` |
| Troubleshooting | `docs/troubleshooting/common-issues.md` |
| Betrieb / Runbooks | `docs/operations/runbook.md` |
| FAQ | `docs/FAQ.md` |
| Roadmap | `docs/roadmap.md` |
| Beispiel-Change | `docs/examples/sample-change.md` |

---

## Support-Hinweis

Dieses Repository ist als **Unternehmens-Blueprint** gedacht: Organisationsspezifische Teams, Variablen und Policies müssen Sie in GitHub und Entra einmalig konfigurieren (`CODEOWNERS`, Branch Protection, Federated Credentials).
