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

## Graph 400 beim Application Segment (POST applicationSegments)

- **Ports:** Graph erwartet `"3389-3389"`, nicht `"3389"`. Im Repo wird `3389` beim Deploy automatisch zu `3389-3389` normalisiert.
- **RDP auf feste IP:** In YAML `type: ipRangeCidr` und `host: 10.0.1.1/32` verwenden (zuverlässiger als `ipAddress` + `10.0.1.1`).
- **Payload:** Kein `@odata.type` im POST (Microsoft Learn); die Pipeline probiert automatisch Varianten.
- **Connector Group** muss mindestens einen **aktiven** Connector enthalten.
- **host/type:** `fqdn` erfordert einen Hostnamen; CIDR-Notation nur mit `ipRangeCidr`.

### `Invalid_AppSegments_NonwebApp_Duplicate` (IP/Port bereits belegt)

**Symptom:** `IP address and port overlaps with existing segment on application` mit `conflictingApplication={ appId, objectId, ... }`.

**Ursache:** Im **gesamten Mandanten** darf dieselbe IP+Port-Kombination (z. B. `10.0.1.1` + TCP `3389`) nur **einmal** als Private-Access-Segment existieren – nicht nur pro Anzeigename.

Das passiert oft nach mehreren Test-Deploys: Sie löschen `PA-NUVATECH-OFFICE-RDP-GERSTHOFEN`, aber eine **ältere/halbfertige** App mit anderem Namen (manchmal nur GUID als Name) hält das Segment noch.

**Lösung:**

1. Im Entra-Portal → **Unternehmensanwendungen** → nach **objectId** oder **appId** aus der Fehlermeldung suchen (nicht nur nach `PA-NUVATECH-…`).
2. Diese **Konflikt-App** löschen (Enterprise Application).
3. Die **neu angelegte** App aus dem fehlgeschlagenen Lauf ebenfalls löschen (objectId/ApplicationId aus dem Pipeline-Log).
4. Deploy erneut starten.

**Alternative:** In der YAML eine andere `host`/`ports`-Kombination verwenden.


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
