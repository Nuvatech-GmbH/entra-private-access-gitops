# Troubleshooting

## `Connector Group wurde nicht gefunden`

- Prüfen Sie exakte Schreibweise von `spec.connectorGroup`.
- Verifizieren Sie im Mandanten: `GET /beta/onPremisesPublishingProfiles/applicationProxy/connectorGroups`.

## `Mehrdeutiger Application-Name`

- `metadata.name` / `displayName` ist nicht eindeutig.
- Setzen Sie `metadata.graphApplicationId` in YAML für eine stabile Bindung.

## Graph `429 Too Many Requests`

- Die Module enthalten exponentielles Backoff.
- Reduzieren Sie Parallelität (dieses Repo deployt sequentiell pro Datei in `Invoke-GSADeployment`).

## YAML validiert lokal, schlägt in CI fehl

- Unterschiedliche `powershell-yaml` Versionen → pinnen Sie Versionen in `build/Invoke-LocalCI.ps1` / CI-Step.

## `powershell-yaml` fehlt

```powershell
Install-Module powershell-yaml -Scope CurrentUser
```

## Graph 403 beim Deploy (PATCH applications/…)

**Häufigste Lösung:** Graph **Application permission** `OnPremisesPublishingProfiles.ReadWrite.All` auf `sp-gsa-gitops-prod` hinzufügen und **Grant admin consent** ausführen. `Application.ReadWrite.All` allein reicht für `onPremisesPublishing` per OIDC/App-only nicht.

Die Pipeline prüft diese Permission vor dem Deploy (`Test-GSAPipelineGraphAppPermissions`).


### Welche App darf gelöscht werden?

| App | Löschen vor Re-Deploy? |
| --- | --- |
| `PA-NUVATECH-OFFICE-RDP-GERSTHOFEN` (Ziel-App) | **Ja** – halbfertige Private-Access-App |
| `sp-gsa-gitops-prod` (Pipeline) | **Nein** – bricht OIDC und Rollenzuweisung |

Das erneute Anlegen von `PA-NUVATECH-…` durch die Pipeline ist **normal** und bedeutet nicht, dass die Pipeline-App fehlt.


**Symptom:** `Microsoft Graph verweigerte die Operation (PATCH https://graph.microsoft.com/beta/applications/...)`

**Checkliste:**

1. **Admin consent** für `Application.ReadWrite.All` und `AppRoleAssignment.ReadWrite.All` auf `sp-gsa-gitops-prod`
2. **Directory-Rolle** dem Service Principal der Pipeline zuweisen: **Application Administrator** (siehe `docs/security/authentication-and-permissions.md`)
3. **Teilweise angelegte App löschen:** Entra → Enterprise applications → `PA-NUVATECH-OFFICE-RDP-GERSTHOFEN` → löschen → Deploy erneut (legt App neu an)
4. **Connector Group** `Office-Gersthofen` muss existieren
5. **Gruppe** aus YAML (`SEC-GSA-PA-OFFICE-RDP-GERSTHOFEN`) muss existieren oder `principalId` setzen

## OIDC Login in GitHub schlägt fehl

- Federated Credential Subject passt nicht zu `ref`, `environment` oder `pull_request`.
- Prüfen Sie Audience / Issuer laut Microsoft-Dokumentation zu GitHub OIDC.
