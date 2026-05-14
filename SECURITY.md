# Security Policy

## Meldung von Schwachstellen

Bitte melden Sie Sicherheitsprobleme **nicht** als öffentliches GitHub Issue, sondern über den internen Security-Kanal Ihrer Organisation (SOC / AppSec).

Enthalten Sie:

- betroffene Komponente (Workflow, Modul, Skript)
- Schritte zur Reproduktion
- potenzielle Auswirkung (CWE-kompatibel wenn möglich)

## Harte Regeln in diesem Repository

- Keine Secrets im Git-Verlauf.
- Keine Client Secrets für Produktionspipelines (OIDC bevorzugt).
- Änderungen an `/.github/workflows/**` und `/modules/**` erfordern erhöhte Aufmerksamkeit (CODEOWNERS).

## Graph Permissions

Siehe `docs/security/authentication-and-permissions.md`.
