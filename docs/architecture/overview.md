# Architekturüberblick

## Problemstellung

Microsoft Entra Private Access (Global Secure Access) beschreibt **Anwendungszugriffe** über Application Proxy / ZTNA-Clients. In Unternehmen wächst die Anzahl der Ziele, Ports und Zuweisungen schnell. Ohne **GitOps** entstehen Undokumentiertheit, Drift und schwierige Audits.

## Lösungsprinzip

1. **Deklarativer Desired State** in YAML unter `config/applications/`.
2. **Automatisierte Qualitätssicherung** in GitHub Actions (Schema, Naming, Duplikate, PSScriptAnalyzer, Pester).
3. **Sichere Authentifizierung** über **OIDC** (föderierte Anmeldeinformationen) an eine dedizierte App Registration mit **Least Privilege**.
4. **Idempotente Reconciliation** über PowerShell-Module, die Microsoft Graph (primär `beta`) nutzen – orientiert am offiziellen Microsoft Learn Tutorial zu Private Access und Graph.

## Referenz zur Microsoft Graph Implementierung

Die Automatisierung folgt den dokumentierten Schritten:

- Custom Application Template (`applicationTemplates` instantiate)
- `onPremisesPublishing.applicationType` (`nonwebapp` / `quickaccessapp`) und ZTNA-Flags
- Connector Group Zuordnung (`onPremisesPublishingProfiles/applicationProxy/connectorGroups`)
- Application Segments (`ipSegmentConfiguration/applicationSegments`)
- Zuweisungen über `appRoleAssignments` am Service Principal

Quelle (Stand Dokumentation): [Configure Microsoft Entra Private Access using Microsoft Graph APIs](https://learn.microsoft.com/en-us/graph/tutorial-entra-private-access)

## Abstraktionsschicht

| Schicht | Verantwortung |
| --- | --- |
| `schemas/*.json` | Strukturelle Kontrakte + CI-Validierung |
| `scripts/validate` | Governance (Naming, Duplikate, Plausibilität) |
| `modules/PrivateAccess` | Graph-spezifische Orchestrierung |
| `modules/PrivateAccess/Private/GraphClient.ps1` | zentraler REST-/SDK-Zugriff (Anpassung bei API-Änderungen) |

## Observability (Konzept)

- **Kurzfristig**: strukturierte JSON-Logs auf STDOUT + Korrelations-ID pro Lauf.
- **Mittelfristig**: Ship von GitHub Actions Logs in **Log Analytics** (Azure Monitor) mittels Diagnostic Settings / Event Hub.
- **Langfristig**: Korrelation mit **Microsoft Sentinel** (Incidents bei wiederholten Graph-429/5xx, fehlgeschlagenen Deployments).

Details siehe `docs/operations/runbook.md`.
