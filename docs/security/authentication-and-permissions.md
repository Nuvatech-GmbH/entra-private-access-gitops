# Authentifizierung und Microsoft Graph Berechtigungen

## Zielbild

- **Keine Client Secrets** im Repository.
- **OIDC / Workload Identity Federation** zwischen GitHub Actions und Microsoft Entra.
- **Least Privilege** für die Pipeline-Identität.

## GitHub → Microsoft Entra (OIDC)

1. Erstellen Sie eine **App Registration** (z. B. `sp-gsa-gitops-prod`).
2. Konfigurieren Sie **Federated Credentials** für `repo:<org>/<repo>:ref:refs/heads/main` und optional `environment:production` / Pull Request Subject (je nach Strategie).
3. In GitHub speichern Sie **keine Secrets** für die reine Authentifizierung; verwenden Sie `azure/login@v2` mit:
   - `client-id` = `vars.GSA_GRAPH_CLIENT_ID`
   - `tenant-id` = `vars.AZURE_TENANT_ID`
   - `allow-no-subscriptions: true` (reiner Graph-Zugriff ohne Azure Subscription)

Die Pipeline holt anschließend ein Graph-Token via Azure CLI (`az account get-access-token --resource-type ms-graph`), das von `Connect-GSAEnvironment` verwendet wird.

## Erforderliche Microsoft Graph Application Permissions (Empfehlung)

> Exakte Namen können je nach Portal-Version variieren – prüfen Sie die App Registration im Portal gegen diese Liste.

| Permission | Zweck |
| --- | --- |
| `Application.ReadWrite.All` | Anwendungen und Segmente verwalten |
| `AppRoleAssignment.ReadWrite.All` | Zuweisungen an Service Principals |
| `Directory.Read.All` | Auflösung von Gruppennamen / UPNs (optional, wenn `principalName` genutzt wird) |

Alternativ (restriktiver, mehr Aufwand): feingranulare Kombinationen aus `Application.Read.All` + gezielte Writes – in der Praxis ist Private Access Automation häufig **Application Administrator** + dedizierte App mit obigen Permissions.

## Administratorrollen in Entra (Menschliche Break-Glass)

Für manuelle Korrekturen sind typischerweise folgende Rollen relevant (siehe Microsoft Learn Tutorial):

- **Application Administrator**
- **Global Secure Access Administrator**

## Geheimnisse

- Keine Secrets im Git.
- Optional: **Azure Key Vault** als GitHub-OIDC-fähiger Secret Store für Sonderfälle (nicht Standard dieses Repos).
