# FAQ

## Warum nur ein Produktiv-Mandant?

Viele Kunden betreiben genau **einen** produktiven Microsoft Entra Tenant. Statt künstlicher Mehrmandantenfähigkeit im Repo priorisieren wir **Sicherheitsgates** (Validierung, WhatIf, Reviews, Environment Protection).

## Warum `beta` Graph?

Microsoft dokumentiert zentrale Private Access Schritte aktuell auf `beta`. Die GraphClient-Schicht kapselt dies – bei GA-Wechseln passen Sie primär URIs und Payload-Mappings an.

## Unterstützt das Repo Quick Access Apps?

Ja, `spec.applicationType: quickAccess` mappt auf `quickaccessapp`. DNS-Resolution Flags sind im Schema optional dokumentiert.

## Reicht Connector Group + grüner Pipeline-Deploy für Nutzerzugriff?

**Nein.** Die Pipeline konfiguriert die **Enterprise Application** (Segmente, Connector-Zuordnung, Gruppe an der App). Zusätzlich brauchen Sie im Mandanten typischerweise:

- **Datenverkehrsprofil für privaten Zugriff** → **aktiviert**
- **Gruppen-Zuweisung an diesem Profil** (getrennt von `spec.assignments`)
- **Global Secure Access Client** auf den Endgeräten (bei `isAccessibleViaZTNAClient: true`)

Siehe [`docs/operations/portal-configuration-after-deploy.md`](operations/portal-configuration-after-deploy.md).

## Wie verhindern wir parallele konkurrierende PRs?

Organisatorisch durch Teamprozesse; technisch durch:

- Duplikat-Erkennung über Ziel-Signaturen
- CODEOWNERS + Branch Protection
- optionale `merge_queue` in GitHub (Empfehlung in `CONTRIBUTING.md`)

## Kann ich Terraform statt PowerShell nutzen?

Dieses Repository ist bewusst auf **Microsoft Graph + PowerShell** standardisiert. Terraform wäre ein paralleles Modell und wird hier nicht mitgeliefert.
