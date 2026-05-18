# Integrationstests (manuell)

Integrationstests richten sich gegen **den produktiven Mandanten** und sollten nur mit Change-Freigabe ausgeführt werden.

## Voraussetzungen

- `Connect-GSAEnvironment` erfolgreich (Azure CLI Token oder interaktiv)
- Test-App mit eindeutigem `metadata.name` Präfix `TEST-PA-...`

## Beispielablauf

```powershell
Import-Module ./modules/PrivateAccess/PrivateAccess.psd1 -Force
Connect-GSAEnvironment -TenantId $env:GSA_TENANT_ID -AuthenticationMode Interactive

Compare-GSAState -ConfigurationPath ./config/applications/<test>.yaml
Invoke-GSADeployment -ApplicationsPath ./config/applications -WhatIf
```

Erwartung: `Compare-GSAState` zeigt `Drift` bis zum ersten erfolgreichen Deployment, danach `InSync`.
