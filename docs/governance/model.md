# Governance-Modell

## Rollen (empfohlen)

| Rolle | Aufgabe |
| --- | --- |
| **Application Owner** | Fachliche Verantwortung, `metadata.owners`, Change-Referenz |
| **Platform Engineering** | Pipeline, Module, Schema, Sicherheitsarchitektur |
| **Security Engineering** | Least Privilege, Threat Modelling, Reviews bei Hochrisiko-Änderungen |
| **CAB / Change Management** | Genehmigung außerhalb von Git (Ticket/RFC) – referenziert über `metadata.changeReference` |

## Pull Request Regeln

- Mindestens **zwei** Reviews für Änderungen unter `config/applications/` (eines davon Platform).
- **CODEOWNERS** erzwingt automatische Review-Anforderungen (GitHub Organization Policy).
- Pflichtfelder in YAML: `owners`, `changeReference`, eindeutiger `metadata.name`.

## Branching

- `main` ist **immer deploybar** und repräsentiert den produktiven Soll-Zustand.
- Feature-Branches: `feature/<ticket>-<kurzbeschreibung>`
- Hotfix-Branches: `hotfix/<ticket>-<kurzbeschreibung>`

## Genehmigungen

- **PR Review** = fachliche + technische Freigabe.
- **GitHub Environment `production`** = operative Freigabe für Mutationen im Mandanten (optional zusätzlich zum PR Merge).

## Auditing

Jeder produktive Lauf erzeugt:

- GitHub Actions Run inkl. Commit SHA
- Artefakt mit Snapshot der YAML-Dateien (`deploy-production.yml`)
- strukturierte Logs mit `correlationId`

Zusätzlich liefert Microsoft Entra eigene Audit Logs (Directory Changes) – diese sollten im SOC-Prozess mit dem Git-Commit korreliert werden.
