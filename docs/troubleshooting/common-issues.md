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

## OIDC Login in GitHub schlägt fehl

- Federated Credential Subject passt nicht zu `ref`, `environment` oder `pull_request`.
- Prüfen Sie Audience / Issuer laut Microsoft-Dokumentation zu GitHub OIDC.
