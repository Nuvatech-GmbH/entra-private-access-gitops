# Demo: vier Anwendungssegment-Typen (Private Access)

Vier produktive YAML-Dateien unter `config/applications/` zeigen die **Zieltypen** aus dem Entra-Portal (Anwendungssegment erstellen) – jeweils als **eigene Enterprise-App**, damit Sie in Demos den Unterschied klar zeigen können.

## Portal ↔ YAML ↔ Graph

| Portal (DE) | `spec.destinations[].type` | `host`-Beispiel (Demo) | Typischer Dienst |
| --- | --- | --- | --- |
| **IP-Adresse** | `ipAddress` | `192.0.2.10` | RDP `3389` |
| **Vollqualifizierter Domänenname** | `fqdn` | `nuvadc01.nuvatech.de` | RDP `3389` (vom Connector erreichbar) |
| **IP-Adressbereich (CIDR)** | `ipRangeCidr` | `198.51.100.0/28` | SMB `445` |
| **IP-Adressbereich (IP zu IP)** | `ipRange` | `203.0.113.10-203.0.113.20` | SSH `22` |

Graph-API-Werte: `ipAddress`, `fqdn`, `ipRangeCidr`, `ipRange` (siehe [ipApplicationSegment](https://learn.microsoft.com/en-us/graph/api/resources/ipapplicationsegment?view=graph-rest-beta)).

## Dateien im Repository

| Datei | `metadata.name` |
| --- | --- |
| `pa-demo-segment-ipaddress.yaml` | `PA-DEMO-SEGMENT-IPADDRESS` |
| `pa-demo-segment-fqdn.yaml` | `PA-DEMO-SEGMENT-FQDN` |
| `pa-demo-segment-iprange-cidr.yaml` | `PA-DEMO-SEGMENT-IPRANGE-CIDR` |
| `pa-demo-segment-iprange-start-end.yaml` | `PA-DEMO-SEGMENT-IPRANGE-START-END` |

**Hinweis:** Dateien ohne `.example.yaml` werden bei Merge nach `main` **deployed**. Für reine Doku-Vorlagen kopieren Sie die Dateien lokal mit Endung `.example.yaml`.

## Vor dem Rollout (Testtenant)

1. **Connector Group** `Office-Gersthofen` (oder in allen YAMLs auf Ihre Gruppe anpassen).
2. **Gruppe** `SEC-GSA-PA-DEMO-USERS` in Entra ID anlegen und Demo-User hinzufügen.
3. **Datenverkehrsprofil** „Privater Zugriff“ aktivieren + Gruppe zuweisen → [`portal-configuration-after-deploy.md`](../operations/portal-configuration-after-deploy.md).
4. **GSA Client** auf Demo-Clients.
5. **RFC5737-Adressen** (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`) im Lab als Ziele/Loopback oder Test-VMs nutzen – sie sind **nicht** im öffentlichen Internet routbar.
6. **Mandantenweite Eindeutigkeit:** Pro IP+Port nur **eine** App – bei `Invalid_AppSegments_NonwebApp_Duplicate` Papierkorb prüfen → [`application-lifecycle-and-purge.md`](../operations/application-lifecycle-and-purge.md).

## Demo-Ablauf (Vorschlag)

1. Vier Apps nacheinander oder per einen PR nach `main` ausrollen lassen.
2. Im Portal unter **Global Secure Access** → **Applications** die vier Enterprise Apps zeigen.
3. Pro App ein Segment öffnen und **Zieltyp / Host / Ports** mit der YAML abgleichen.
4. Optional: eine App live ändern (nur Ports in YAML) → zweiter Deploy zeigt GitOps-Reconcile.

## Anpassungen für Ihre Umgebung

| Feld | Empfehlung |
| --- | --- |
| `spec.connectorGroup` | Name Ihrer echten Connector Group |
| `assignments.principalName` | Ihre Demo-Gruppe, besser `principalId` (GUID) |
| `owners` | Ihre Plattform-Mail |
| `host` (FQDN) | `nuvadc01.nuvatech.de` (oder anderer vom Connector auflösbarer/erreichbarer Host) |
| Produktiv-RDP | Weiterhin `pa-nuvatech-office-rdp-gersthofen.yaml` mit echter IP |

## Einzel-IP: `ipAddress` vs. `ipRangeCidr /32`

Für **eine** feste IPv4 (z. B. RDP) ist in der Praxis oft `ipRangeCidr` + `10.0.1.1/32` zuverlässiger als `ipAddress` (siehe Troubleshooting). Die Demo-Datei `pa-demo-segment-ipaddress.yaml` nutzt bewusst **`ipAddress`**, um den Portal-Typ 1:1 abzubilden; die Pipeline probiert bei Bedarf automatisch `/32` als Fallback.
