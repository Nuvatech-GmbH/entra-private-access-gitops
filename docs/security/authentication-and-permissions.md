# Authentifizierung und Microsoft Graph Berechtigungen

## Zielbild

- **Keine Client Secrets** im Repository.
- **OIDC / Workload Identity Federation** zwischen GitHub Actions und Microsoft Entra.
- **Least Privilege** für die Pipeline-Identität.

---

## Teil 1: Microsoft Entra (App Registration)

### 1.1 App Registration

Erstellen Sie eine App Registration (z. B. `sp-gsa-gitops-prod`) im **Zielmandanten** (Kunde oder interner Tenant).

Notieren Sie:

- **Directory (tenant) ID** → wird `AZURE_TENANT_ID` in GitHub
- **Application (client) ID** → wird `GSA_GRAPH_CLIENT_ID` in GitHub

### 1.2 Federated Credentials (GitHub OIDC)

Unter **Certificates & secrets** → **Federated credentials** → Szenario **GitHub Actions deploying Azure resources**.

**Issuer:** `https://token.actions.githubusercontent.com`  
**Organization / Repository:** Ihre GitHub-Org und dieses Repo (z. B. `Nuvatech-GmbH` / `entra-private-access-gitops`).

Empfohlen: **zwei** Credentials (eng begrenzt):

| Zweck | Entity type | Name / Wert | Subject (Beispiel) |
| --- | --- | --- | --- |
| Produktions-Deploy | **Environment** | `production` | `repo:Nuvatech-GmbH/entra-private-access-gitops:environment:production` |
| PR WhatIf / Drift | **Pull request** | (automatisch) | `repo:Nuvatech-GmbH/entra-private-access-gitops:pull_request` |

Alternativ nur zum schnellen Test: **Branch** `main` – dann funktionieren PR-Workflows mit Graph auf Feature-Branches **nicht**.

**Audience:** `api://AzureADTokenExchange` (Standard belassen).

### 1.3 Microsoft Graph API permissions

**API permissions** → **Microsoft Graph** → **Application permissions** (nicht Delegated).

| Permission | Zweck |
| --- | --- |
| `Application.ReadWrite.All` | Apps, `onPremisesPublishing`, Application Segments |
| `AppRoleAssignment.ReadWrite.All` | Zuweisungen an Service Principals |
| `Directory.Read.All` | Optional: Auflösung von `principalName` in YAML |

Engere Alternative zu `Directory.Read.All`: `User.Read.All` + `Group.Read.All`, wenn Sie nur UPN/Gruppennamen auflösen.

Anschließend: **Grant admin consent for &lt;Tenant&gt;**.

### 1.4 Entra Directory-Rolle für die Pipeline (häufig erforderlich)

Für **Private Access**-Eigenschaften (`onPremisesPublishing`, ZTNA, Application Segments) reichen in der Praxis oft **nur** Graph Application permissions **nicht** aus.

Weisen Sie dem **Service Principal** Ihrer Pipeline-App (`sp-gsa-gitops-prod`) zusätzlich eine Directory-Rolle zu:

| Directory-Rolle | Empfehlung |
| --- | --- |
| **Application Administrator** | Standard für App-Registrierungen / Application Proxy / Private Access Automation |
| Global Secure Access Administrator | Optional zusätzlich, wenn weiterhin 403 auf GSA-spezifische Einstellungen |

**Pfad:** Microsoft Entra admin center → **Roles and administrators** → **Application Administrator** → **Add assignments** → Mitglied = Enterprise Application Ihrer Pipeline-App (nicht nur die App Registration).

> Das Microsoft Learn Tutorial nutzt interaktive Admin-Konten mit diesen Rollen. Service Principals benötigen dieselbe Effektivberechtigung über **App permissions + Directory role assignment**.

### 1.4 Wie die Pipeline authentifiziert

Die Workflows nutzen `azure/login@v2` mit:

- `client-id` = `vars.GSA_GRAPH_CLIENT_ID`
- `tenant-id` = `vars.AZURE_TENANT_ID`
- `allow-no-subscriptions: true`

Danach holt `Connect-GSAEnvironment` ein Graph-Token via `az account get-access-token --resource-type ms-graph`.

---

## Teil 2: GitHub (nach Entra)

### 2.1 Repository-Variablen

Repository → **Settings** → **Secrets and variables** → **Actions** → **Variables** → **New repository variable**

| Name | Wert |
| --- | --- |
| `AZURE_TENANT_ID` | Directory (tenant) ID aus Entra |
| `GSA_GRAPH_CLIENT_ID` | Application (client) ID von `sp-gsa-gitops-prod` |

Keine Secrets für OIDC erforderlich.

### 2.2 Environment `production`

**Settings** → **Environments** → **New environment** → Name: **`production`**

- **Required reviewers** aktivieren
- Optional: Deployment nur von Branch **`main`**

Entspricht `.github/workflows/deploy-production.yml` (`environment: production`).

### 2.3 Actions

**Settings** → **Actions** → **General**: Actions für das Repository erlauben.

`id-token: write` ist in den Workflow-YAML-Dateien bereits gesetzt.

### 2.4 Erster Test

| Schritt | Aktion | Erwartung |
| --- | --- | --- |
| 1 | **Actions** → **validation** → **Run workflow** | Grün ohne Entra |
| 2 | PR mit Änderung unter `config/applications/` | `call-validation` grün; `what-if-comment` nur mit Federated Credential **Pull request** |
| 3 | Merge nach `main` | **deploy-production** startet |
| 4 | Run öffnen → **Approve** Environment `production` | Graph-Deploy läuft |

### 2.5 Nicht in GitHub konfigurieren

- `AZURE_CLIENT_SECRET`
- `AZURE_SUBSCRIPTION_ID`
- Separates Graph-API-Secret

---

## Teil 3: Fehlerbilder

| Symptom | Prüfen |
| --- | --- |
| OIDC / Azure Login failed | Federated Credential Subject vs. Branch/Environment/PR |
| Variable nicht gesetzt | Schreibweise `AZURE_TENANT_ID`, `GSA_GRAPH_CLIENT_ID` |
| HTTP 403 von Graph | Admin consent, Application vs. Delegated permissions |
| Connector Group nicht gefunden | Manuelle Anlage im Portal; exakter Name in YAML `spec.connectorGroup` |

---

## Administratorrollen in Entra (Menschliche Break-Glass)

Für manuelle Korrekturen im Portal (Connectors, Connector Groups):

- **Application Administrator**
- **Global Secure Access Administrator**

Die Pipeline benötigt diese **Benutzerrollen** nicht – nur die **Application permissions** an der App Registration.

---

## Geheimnisse

- Keine Secrets im Git für Standard-OIDC.
- Optional: Azure Key Vault als Secret Store für Sonderfälle (nicht Standard dieses Repos).
