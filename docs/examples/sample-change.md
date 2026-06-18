# Beispiel: Änderung an Ports (Change)

## Ausgangslage

Die Anwendung `PA-CONTOSO-HR-PORTAL` soll zusätzlich `TCP/8443` erlauben (Staging eines neuen Listeners).

## Schritte

1. Branch `feature/CHG-204512-hr-port-8443` von `main`.
2. YAML `config/applications/pa-contoso-hr-portal.yaml` anpassen:

```yaml
spec:
  destinations:
    - host: hr.contoso.corp
      type: fqdn
      ports: ["443", "8443"]
      protocol: tcp
```

3. Lokal `pwsh ./build/Invoke-LocalCI.ps1`.
4. PR mit ausgefüllter Vorlage, Security Review bei Port-Erweiterungen.
5. Nach Merge: Deployment läuft automatisch (Environment Approval).

## Rollback

Revert des Commits oder Entfernen von `8443` erneut mergen.
