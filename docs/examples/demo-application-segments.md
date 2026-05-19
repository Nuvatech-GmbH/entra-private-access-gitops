# Demo: vier Anwendungssegment-Typen (Private Access)

Vier YAML-Dateien unter `config/applications/` – je **ein Zieltyp**, **keine überlappenden IP+Port-Kombinationen** im Mandanten (wichtig für Graph).

## Voraussetzungen (einmalig)

| Punkt | Wert |
| --- | --- |
| Connector Group | `Office-Gersthofen` (in allen YAMLs – anpassen falls anders) |
| Gruppe | `SEC-GSA-PA-DEMO-USERS` in Entra anlegen + Demo-User |
| GSA Profil | Privater Zugriff **aktiviert**, Gruppe zugewiesen → [`portal-configuration-after-deploy.md`](../operations/portal-configuration-after-deploy.md) |
| Papierkorb | Alte Demo-Apps/`deletedItems` bereinigt → [`application-lifecycle-and-purge.md`](../operations/application-lifecycle-and-purge.md) |

## Die vier Demo-Apps

| Portal-Zieltyp | Datei | App-Name | Ziel | Port | Demo-Szenario |
| --- | --- | --- | --- | --- | --- |
| **FQDN** | `pa-demo-segment-fqdn.yaml` | `PA-DEMO-SEGMENT-FQDN` | `nuvadc01.nuvatech.de` | 3389 | RDP zum echten DC (Connector-Test) |
| **IP-Adresse** | `pa-demo-segment-ipaddress.yaml` | `PA-DEMO-SEGMENT-IPADDRESS` | `192.168.178.42` | 3389 | RDP zum Connector-Win-Server (Host-IP) |
| **CIDR** | `pa-demo-segment-iprange-cidr.yaml` | `PA-DEMO-SEGMENT-IPRANGE-CIDR` | `10.0.2.0/28` | 389 | LDAP auf Subnetz |
| **IP zu IP** | `pa-demo-segment-iprange-start-end.yaml` | `PA-DEMO-SEGMENT-IPRANGE-START-END` | `192.168.178.40-192.168.178.50` | 5985 | WinRM auf IP-Bereich (Connector-LAN) |

**Hinweis IP + FQDN:** `192.168.178.42:3389` (IP-Demo) und `nuvadc01.nuvatech.de:3389` (FQDN-Demo) kollidieren im Mandanten, wenn der FQDN **dieselbe IP** auflöst. Dann eine der beiden Apps anpassen oder nur eine mit Port 3389 deployen. Die übrigen Demos (`10.0.2.0/28:389`, `192.168.178.40-50:5985`) bleiben unabhängig.

**Hinweis `ipRange`:** Graph lehnt `destinationType: ipRange` mit `host: 10.0.3.10-10.0.3.20` oft mit 400 ab. Das Modul probiert alternative Schreibweisen und legt bei Bedarf ein **passendes `ipRangeCidr`** an (z. B. `192.168.178.32/27` für `192.168.178.40-50`). In YAML bleibt `type: ipRange` für den Portal-Typ „IP zu IP“.

## Portal ↔ YAML

| Portal (DE) | `spec.destinations[].type` |
| --- | --- |
| IP-Adresse | `ipAddress` |
| Vollqualifizierter Domänenname | `fqdn` |
| IP-Adressbereich (CIDR) | `ipRangeCidr` |
| IP-Adressbereich (IP zu IP) | `ipRange` (`host`: `192.168.178.40-192.168.178.50`) |

## Deploy

0. **Keine Duplikate:** Pro `metadata.name` (z. B. `PA-DEMO-SEGMENT-FQDN`) darf im Mandanten nur **eine** Application existieren. Nach Testläufen alle Doppelungen + Papierkorb bereinigen, sonst bricht der Deploy mit „Mehrere Entra-Applications mit displayName …“ ab.
1. PR/Merge nach `main` → `deploy-production` deployt **alle** `pa-demo-*.yaml` (nicht `*.example.yaml`).
2. Bei Fehler `Invalid_AppSegments_NonwebApp_Duplicate`: Konflikt-App aus Log + Papierkorb löschen.
3. Nach Erfolg optional `metadata.graphApplicationId` in jede YAML eintragen (stabile Updates).

## Anpassung an euer Netz

- **`192.168.178.42`**: IP des Connector-Win-Servers – für die IP-Adress-Demo bewusst gewählt (lokal erreichbar).
- **`10.0.2.0/28`**: Beispiel-CIDR – anpassen, falls im Mandanten schon belegt.
- **`192.168.178.40-50`**: kleiner Bereich im Connector-LAN (Graph speichert oft als `ipRangeCidr`, z. B. `192.168.178.32/27`).
