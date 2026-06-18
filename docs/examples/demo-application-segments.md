# Demo: vier Anwendungssegment-Typen (Private Access)

Vier Beispiel-YAMLs unter `config/examples/` – je **ein Zieltyp**. Dateien enden auf `*.example.yaml` und werden **nicht** automatisch deployed.

## Voraussetzungen (einmalig)

| Punkt | Wert |
| --- | --- |
| Connector Group | `CG-EU-CENTRAL-PA-PROD-01` (in allen YAMLs anpassen) |
| Gruppe | `SEC-GSA-PA-DEMO-USERS` in Entra anlegen |
| GSA Profil | Privater Zugriff **aktiviert**, Gruppe zugewiesen → [`portal-configuration-after-deploy.md`](../operations/portal-configuration-after-deploy.md) |

## Die vier Demo-Apps

| Portal-Zieltyp | Datei | App-Name | Ziel | Port |
| --- | --- | --- | --- | --- |
| **FQDN** | `pa-demo-segment-fqdn.example.yaml` | `PA-DEMO-SEGMENT-FQDN` | `dc01.contoso.corp` | 3389 |
| **IP-Adresse** | `pa-demo-segment-ipaddress.example.yaml` | `PA-DEMO-SEGMENT-IPADDRESS` | `192.168.10.42` | 3389 |
| **CIDR** | `pa-demo-segment-iprange-cidr.example.yaml` | `PA-DEMO-SEGMENT-IPRANGE-CIDR` | `10.0.2.0/28` | 389 |
| **IP zu IP** | `pa-demo-segment-iprange-start-end.example.yaml` | `PA-DEMO-SEGMENT-IPRANGE-START-END` | `10.0.3.10-10.0.3.20` | 5985 |

## Deploy

1. Beispiel kopieren: `cp config/examples/pa-demo-segment-fqdn.example.yaml config/applications/pa-meine-demo.yaml`
2. Werte an Mandant anpassen (Connector Group, Ziele, Gruppe)
3. PR/Merge nach `main` → `deploy-production` deployt nur YAMLs **ohne** `*.example.yaml`

## Portal ↔ YAML

| Portal (DE) | `spec.destinations[].type` |
| --- | --- |
| IP-Adresse | `ipAddress` |
| Vollqualifizierter Domänenname | `fqdn` |
| IP-Adressbereich (CIDR) | `ipRangeCidr` |
| IP-Adressbereich (IP zu IP) | `ipRange` |
