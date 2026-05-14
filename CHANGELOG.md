# Changelog

Alle wesentlichen Änderungen an diesem Repository werden hier dokumentiert (Format inspiriert von Keep a Changelog).

## [1.0.0] - 2026-05-14

### Added

- Initiales **GitOps** Repository für Microsoft Entra Private Access (Global Secure Access) mit YAML Desired State.
- PowerShell 7 Module `Common` und `PrivateAccess` inkl. Graph Reconciliation (siehe Microsoft Learn Tutorial).
- GitHub Actions: `validation.yml`, `pull-request-validation.yml`, `deploy-production.yml` mit OIDC via `azure/login`.
- JSON Schema `schemas/private-access-application.schema.json` und Validierungsskript `scripts/validate/Invoke-GSAValidation.ps1`.
- Pester Unit Tests und lokales CI-Skript `build/Invoke-LocalCI.ps1`.
- Umfangreiche Dokumentation unter `docs/`.
