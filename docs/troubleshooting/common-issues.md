# Troubleshooting

## Deploy erfolgreich, aber Nutzer kommen nicht auf die App (RDP / internes Ziel)

**Häufigste Ursachen (Portal, nicht YAML):**

1. **Profil für privaten Zugriff** unter Global Secure Access → Verbinden → Datenverkehrsweiterleitung ist **deaktiviert**.
2. Am Profil sind **0 Benutzer / 0 Gruppen** zugewiesen (Gruppe nur an der Enterprise App, nicht am Profil).
3. **Global Secure Access Client** fehlt auf dem Client, obwohl `isAccessibleViaZTNAClient: true`.
4. Connector in der Connector Group ist **nicht aktiv**.

Vollständige Checkliste: [`docs/operations/portal-configuration-after-deploy.md`](../operations/portal-configuration-after-deploy.md)

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
- **POST ohne Segment-ID / „kein Treffer per GET“:** Graph speichert Ports oft als `443-443`, YAML hat `443` – ab Repo-Fix werden Port-Signaturen normalisiert; bei Bedarf GET mit kurzer Wartezeit. Halbfertige App `PA-DEMO-…` ggf. löschen und erneut deployen.

### `Invalid_AppSegments_NonwebApp_Duplicate` (IP/Port bereits belegt)

**Symptom:** `IP address and port overlaps with existing segment on application` mit `conflictingApplication={ appId, objectId, ... }`.

**Ursache (normal):** Im **gesamten Mandanten** darf dieselbe IP+Port-Kombination (z. B. `10.0.1.1` + TCP `3389`) nur **einmal** als Private-Access-Segment existieren – nicht nur pro Anzeigename.

**Ursache (häufig bei Ihnen im Test): Verwaiste Segmente im GSA-Backend**

Microsoft bestätigt: Das Löschen unter **Entra → Unternehmensanwendungen** oder **App-Registrierungen** entfernt **Application Segments im Global-Secure-Access-Backend nicht zuverlässig**. Die Konflikt-`appId`/`objectId` kann im Portal **nirgends auffindbar** sein – Graph meldet sie trotzdem, weil das **Segment noch im GSA-Dienst** existiert (orphaned segment).

Typisches Muster:

- Mehrere Test-Apps / Portal-Anlage / fehlgeschlagene Pipeline-Läufe
- App im Portal gelöscht, **Segment-Reservierung bleibt**
- **Jede neue IP** scheitert mit **derselben** `conflictingApplication` → die Geister-App hält **mehrere** Segmente oder der Backend-Index zeigt immer dieselbe Blocker-App
- `appName` in der Fehlermeldung = **GUID** (kein `displayName` gesetzt) → Suche nach Namen findet nichts

Das ist **kein** „Graph liest alte Daten“ im Sinne von Cache – es ist ein **getrennter GSA-Service-Plane-Zustand**, der schlechter mit Entra-UI synchronisiert ist als erwartet.

**Lösung (empfohlene Reihenfolge):**

1. **IDs aus dem Fehlerlog notieren** (`objectId`, `appId` aus `conflictingApplication`).
2. **Diagnose-Skript** (mit `Connect-MgGraph` und ausreichenden Rechten):

   ```powershell
   pwsh ./scripts/admin/Invoke-GSASegmentConflictDiagnostics.ps1 `
     -ConflictObjectId 'f8473034-5426-4d77-912c-7c323b8ec6dd' `
     -ConflictAppId '84ba0dce-1e90-45a6-87a8-6f2020d3b918'
   ```

3. **Papierkorb leeren (häufig der entscheidende Schritt):**
   - **App-Registrierungen** → **Gelöschte Anwendungen** → nach `appId`/`objectId` suchen → **Endgültig löschen (Purge)**
   - Das ist **korrekt** und bewusst **manuell** – die Deploy-Pipeline macht das **nicht** automatisch (siehe [`application-lifecycle-and-purge.md`](../operations/application-lifecycle-and-purge.md))
4. **Suche im Portal (weitere Pfade):**
   - **Unternehmensanwendungen** → Filter **Objekt-ID** = `objectId` (nicht Anzeigename)
   - **Global Secure Access** → **Applications** → **Enterprise applications** (nicht nur Entra Enterprise Apps)
5. Wenn das Skript **Segmente listet**: mit `-RemoveSegmentsOnConflictApp` löschen (benötigt `Application.ReadWrite.All`) **oder** Microsoft Entra PowerShell Beta: `Remove-EntraBetaPrivateAccessApplicationSegment` ([GSA PowerShell-Doku](https://microsoft.github.io/GlobalSecureAccess/Entra%20Private%20Access/powershell/)).
6. **Neu angelegte** Apps aus fehlgeschlagenen Pipeline-Läufen ebenfalls bereinigen (aktiv + Papierkorb).
7. Deploy erneut starten.

**Wenn Graph keine Segmente listet, der Fehler aber bleibt:**

- **Garbage Collection** im GSA-Backend (kann **mehrere Tage** dauern – Microsoft Q&A)
- **Microsoft Support** mit `request-id` aus dem Fehler und `conflictingApplication`

**Prävention:**

- Private-Access-Apps und Segmente möglichst **nur** über GSA → Applications → Enterprise applications **oder** dieses GitOps-Repo verwalten
- Nicht nur unter „Entra Enterprise Applications“ anlegen/löschen und GSA-Blade erwarten

**Alternative:** Andere `host`/`ports` – hilft nur, wenn **diese** Kombination noch nicht von einem verwaisten Segment belegt ist.

Referenz: [Microsoft Q&A – Can't add application segment (orphaned segment)](https://learn.microsoft.com/en-us/answers/questions/5844326/cant-add-new-application-segment-to-global-secure.html)


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
