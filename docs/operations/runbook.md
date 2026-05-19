# Operations Runbook

## Standard-Deployment

- Merge nach `main` löst `deploy-production.yml` aus.
- Voraussetzung: GitHub Environment `production` ist mit **Required Reviewers** konfiguriert.
- **Nach grünem Deploy:** Mandantenweite GSA-Einstellungen (Datenverkehrsprofil, Profil-Zuweisungen, Clients) sind **nicht** Teil der Pipeline – siehe [`portal-configuration-after-deploy.md`](portal-configuration-after-deploy.md).

## Rollback

**Primärstrategie (GitOps):**

1. Revert des fehlerhaften Commits auf `main` (oder neuer PR mit Korrektur).
2. Merge → Pipeline reconciliert den vorherigen Desired State zurück.

**Sekundärstrategie (Break-Glass):**

- Manuelle Korrektur im Entra Admin Center nur wenn Git nicht verfügbar ist.
- Anschließend **Drift beseitigen**: Entweder Git nachziehen oder Import über `metadata.graphApplicationId`.

## Emergency Change

1. Hotfix-Branch von `main`.
2. Minimaler Diff, klarer `changeReference`.
3. Nach Deployment: Post-Mortem + Nachziehen der Dokumentation.

## Monitoring-Konzept

- GitHub Actions: Fehlschläge als Incident-Quelle.
- Microsoft Entra Audit Logs: Korrelation mit `correlationId` über Zeitstempel/Principal der Pipeline-App.

## Optionale Löschungen

`Remove-GSAPrivateAccessApplication` ist bewusst destruktiv und **nicht** Teil des Standard-Deploy-Skripts.

**Papierkorb (Purge):** Die Pipeline purgt **keine** `directory/deletedItems` automatisch. Nach Test-/Konflikt-Bereinigung Apps unter **App-Registrierungen → Gelöschte Anwendungen** manuell endgültig löschen – oder gezielt:

```powershell
Remove-GSAPrivateAccessApplication -ApplicationId '<objectId>' -PurgeFromRecycleBin -RecycleBinOnly
```

Entscheidung und Begründung: [`application-lifecycle-and-purge.md`](application-lifecycle-and-purge.md).
