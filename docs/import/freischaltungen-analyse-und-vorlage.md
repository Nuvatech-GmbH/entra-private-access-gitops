# Freischaltungen.xlsx – Analyse, Zielmodell und BA-Arbeitsanleitung

Stand: Analyse der Datei `import/excel/Freischaltungen.xlsx` gegen das bestehende GitOps-Projekt.

---

## Teil 1 – Analyse der bestehenden Excel

### Blätter

| Blatt | Zeilen | Zweck |
|-------|--------|-------|
| **Rollen und Berechtigung** | 50 | Hinweise/Notizen für Bearbeiter – **keine Freischaltungsdaten** |
| **Firewall** | **1.974** | Relevante Freischaltungen – **einzige Import-Quelle** |

### Spalten (Blatt „Firewall“)

| Spalte | Inhalt | Automatisierung |
|--------|--------|-----------------|
| **Nr.** | Regelnummer (z. B. 89, 92, 97) | Gruppierung, `changeReference`, Tags |
| **Admin Rolle** | Fachrolle (z. B. `Waagensysteme`, `Datenbank-Administratoren`) | 1 App-Gruppe pro Rolle+Einheit |
| **Entra ID - Rollen Name** | Entra-Gruppe – **in allen 1.974 Zeilen befüllt** | `assignments.principalName` |
| **Ziel (DNS-Name/IP/Netze)** | Zielsysteme – sehr heterogen | `destinations[].host` + `type` |
| **Port** | Ports – oft Freitext | `destinations[].ports[]` |
| **Protokoll** | Transport – oft Anwendungsnamen statt tcp/udp | `destinations[].protocol` |
| **Einheit** | Standort/Bereich (MI, SW, HR, …) | `connectorGroup` (via Mapping) |
| **Geprüft** | Review-Status | Meist leer – für neue Vorlage nutzen |
| **Im RegSupport vorhanden** | Referenz | Optional, nicht für Deploy |
| **Nutzung RegSupport** | Referenz | Optional |

### Zahlen & Muster (Firewall)

| Kennzahl | Wert |
|----------|------|
| Admin-Rollen (eindeutig) | **45** |
| Kombinationen Rolle + Einheit | **231** |
| Regelblöcke (Nr. + Rolle + Einheit, Forward-Fill) | **486** |
| Zeilen mit mehrzeiligem Ziel | **193** |
| Zeilen mit leerem Port | **30** |
| Zeilen mit leerem Protokoll | **49** |
| Größte Rolle gesamt | **Waagensysteme: 1.087 Ziele** |

### Vorkommende Zieltypen (heuristisch)

| Muster | Häufigkeit | Beispiel |
|--------|------------|----------|
| FQDN + IP in einer Zelle | sehr häufig | `adminsrv-helpdesk.n.edeka.net / 10.57.86.233` |
| CIDR / Subnetz | sehr häufig | `10.61.216.0/24`, `10.59.0.0/16` |
| Mehrere CIDRs kommagetrennt | häufig | `10.56.23.0/24, 10.56.29.0/24` |
| Nur FQDN | häufig | `rrsgheitjh.gh.rr.edekanet.de` |
| FQDN (IP in Klammern) | häufig | `visrzsnowapp01.rs.edeka.net (10.125.145.174)` |
| URLs | häufig | `https://confluence.edeka-rr.de/` |
| Mehrere FQDNs zeilenweise | häufig | 10+ Hosts in einer Zelle |
| IP-Liste kommagetrennt | mittel | `10.251.16.89, 10.251.16.207` |
| Wildcard | 24 | `10.78.128.*` |
| UNC-Pfade | mittel | `\\sw.edeka.net\EHG\APPS` |
| NetBIOS ohne Domain | selten | `RRSGHDL01-MO`, `nbstsm01` |
| Nur Beschreibung | 18 | `Alle EH Netze`, `wird noch ergänzt` |

### Problematische Port-Angaben

- Freitext: `RDP 3389 und 3333 usw.`, `Enterprise Manager Standard Port Range: 7101-7500`
- Trennzeichen falsch: `80.443`, `443.22`
- Keine Zahl: `ANY`, `Standardport`, `n`
- Port in URL statt eigener Spalte: `http://10.32.110.47:8000/`

### Problematische Protokoll-Angaben

Die Spalte enthält oft **Anwendungsprotokolle**, nicht Transport:

| Wert in Excel | Bedeutung für YAML |
|---------------|-------------------|
| `TCP` / `TCP/UDP` | → `tcp` bzw. `tcp` + `udp` (2 Zeilen) |
| `RDP`, `HTTPS`, `SSH`, `HTTP` | → Port ableiten, Transport = `tcp` |
| `SMB`, `SQL`, `Oracle` | → Ports manuell, Transport `tcp` |
| `???`, `Forescout NAC über GUI/APP` | → `needs_clarification` |

**295 von 1.974 Zeilen** haben kein einfaches `tcp`/`udp`/`tcp/udp`.

### Problematische Einheiten

- Mehrfachwerte: `NB, SB, SW, NO, MI, RR, HR` → **6 Zeilen** in Zielvorlage
- Ungültig: `ungültig`
- Mehrzeilig: `Nord\nNord\nNord`

---

## Teil 2 – Bewertung des Zielmodells

### Eine Entra App pro Admin-Rolle?

| Kriterium | Bewertung |
|-----------|-----------|
| Organisatorisch | Verständlich („eine Rolle = ein Paket“) |
| Technisch | **Nicht für alle Rollen möglich** |
| Graph-Limit | Max. **500 Segmente pro App** |
| Konkret | **Waagensysteme: 1.087 Ziele** → eine App reicht nicht |

**Empfehlung:** **Nicht** pauschal eine App pro Rolle, sondern:

```
1 Private Access Application = Admin Rolle + Einheit (+ optional Nr. als Tag)
```

- Ergibt ca. **231 Apps** statt 45
- Größter Block: Waagensysteme+SW = **240 Segmente** (unter 500)
- Passt zu Connector-Gruppen pro Standort/Bereich

### Mehrere Ziele pro App?

**Ja – das ist der Normalfall** und entspricht dem YAML-Schema (`destinations[]`).

### FQDN vs. IP – technische Empfehlung

| Aspekt | FQDN | IP |
|--------|------|-----|
| Stabilität | Bleibt gültig bei IP-Wechsel, wenn DNS gepflegt | Bricht bei IP-Wechsel |
| Private Access | Connector löst DNS im Zielnetz auf | Direktes Routing zur IP |
| NetBIOS-Kurznamen | Nicht unterstützt – FQDN nötig | Nur wenn feste IP bekannt |
| URLs (`https://…`) | Host extrahieren → `fqdn` | Nicht die URL als Ganzes |

**Klare Empfehlung:** Wenn **FQDN und IP** gemeinsam stehen → **nur FQDN** als Segment (`target_type=fqdn`), IP in `source_reference`/`review_comment` dokumentieren, **kein zweites IP-Segment** für dasselbe System.

Ausnahme: Es gibt **keinen** DNS-Namen (nur IP) → `ipAddress` oder `ipRangeCidr/32`.

### CIDR, IP-Range, Einzel-IP

| Typ | Wann | YAML `type` |
|-----|------|-------------|
| CIDR | `10.61.216.0/24` | `ipRangeCidr` |
| IP von/bis | `10.0.3.10` – `10.0.3.20` | `ipRange` |
| Einzel-IP | `192.168.178.42` | `ipAddress` (Deploy nutzt oft `/32`) |
| Große /16-Netze | `10.59.0.0/16` | Technisch möglich, aber **Sicherheitsreview** – ggf. verkleinern |

### Ports & Protokolle

- Pro Zeile in der Zielvorlage: **genau ein Transportprotokoll** (`tcp` oder `udp`)
- `TCP/UDP` in Original → **zwei Zeilen** (gleiches Ziel, gleicher Port)
- Port als Zahl oder Bereich (`3389` + leer, oder `5900` + `5905`)

### Unvollständige Angaben

→ `review_status=needs_clarification`, `needs_clarification=yes`, Kommentar pflicht.  
**Nicht** mit `approved` exportieren.

---

## Teil 3 – Finales Excel-Zielformat (vereinfacht)

**Datei:** `import/templates/Freischaltungen-Zielvorlage.csv` (Trennzeichen `;`, UTF-8)

**Vom BA-Studenten auszufüllen – keine IDs, kein App-Name, keine Description:**

| Spalte | Pflicht | Beschreibung | Beispiel |
|--------|---------|--------------|----------|
| `admin_rolle` | ja | Spalte „Admin Rolle“ (Firewall) | `Datenbank-Administratoren` |
| `entra_group_name` | ja | Spalte „Entra ID - Rollen Name“ (Firewall) bzw. Blatt „Rollen und Berechtigung“ | `EIT_PA_Admin_INS_Infrastrukturdienste_Datenbanken` |
| `connector_group` | ja | Connector Group im Mandanten | `Office-Gersthofen` |
| `target_type` | ja | `fqdn` \| `ipAddress` \| `ipRangeCidr` \| `ipRange` \| `dnsSuffix` | `fqdn` |
| `fqdn` | bedingt | Hostname (ohne `https://`) | `sql01.n.edeka.net` |
| `ip_address` | bedingt | Einzel-IPv4 | `192.168.178.42` |
| `cidr_range` | bedingt | CIDR | `10.61.216.0/24` |
| `ip_range_start` / `ip_range_end` | bedingt | IP-Bereich | `10.0.3.10` / `10.0.3.20` |
| `protocol` | ja | Nur `tcp` oder `udp` | `tcp` |
| `port` / `port_range_end` | ja* | Port oder Bereich | `3389` / leer |
| `source_reference` | empfohlen | Original-Zelle aus Firewall (Audit) | `…` |
| `review_status` | ja | `pending` \| `approved` \| `needs_clarification` | `approved` |
| `needs_clarification` | ja | `yes` \| `no` | `no` |
| `review_comment` | bedingt | Pflicht bei `needs_clarification=yes` | `Port unklar` |

**Automatisch vom Skript – nicht vom BA ausfüllen:**

| Abgeleitet | Regel |
|------------|-------|
| `metadata.name` (Application) | `{entra_group_name}_{connector_group}` → z. B. `EIT_PA_Admin_INS_Infrastrukturdienste_Datenbanken_Office_Gersthofen` |
| `metadata.description` | `Import: {admin_rolle} / {connector_group}` |
| YAML-Dateiname | aus Application-Name generiert |

### Entra-Gruppenname (Referenz Formel Excel)

Blatt **Rollen und Berechtigung**, Spalte I:

```
EIT_PA_Admin_{E2 Bereich}_{E3 Bereich}_{E4 Bereich?}_{Kurzname?}
```

Entspricht der Excel-Formel: `TEXTKETTE("EIT_PA_Admin_";A;…;E)`.

### App-Gruppierung

**1 Application = `entra_group_name` + `connector_group`** (nicht Einheit, nicht Nr.).

---

## Teil 4 – Validierungsregeln

### target_type

| target_type | Pflichtfelder | Leer lassen |
|-------------|---------------|-------------|
| `fqdn` | `fqdn` | ip_*, cidr_*, ip_range_* |
| `ipAddress` | `ip_address` | fqdn, cidr, ip_range |
| `ipRangeCidr` | `cidr_range` | fqdn, ip_address, ip_range |
| `ipRange` | `ip_range_start`, `ip_range_end` | fqdn, ip_address, cidr |
| `dnsSuffix` | `fqdn` (Suffix) | ip_* |

### FQDN vor IP

- Beide im Original → **eine Zeile** `target_type=fqdn`, `preferred_target=fqdn`
- IP-Felder leer lassen

### Automatisierung blockieren wenn

- `review_status` ≠ `approved`
- `needs_clarification` = `yes`
- Pflichtfeld leer
- `protocol` nicht tcp/udp
- `port` keine Zahl 1–65535
- App hat >500 `approved` Zeilen
- `target_type` passt nicht zu befüllten Feldern

### Ungültige Kombinationen

- `approved` + `needs_clarification=yes`
- `fqdn` + befüllte `ip_address` (Warnung)
- Mehrere `einheit` in einer Zeile
- URL als fqdn ohne Host-Extraktion (`https://…` → nur Hostname eintragen)

### Mehrere Ports

- **Nicht** in eine Zelle: je Port (oder Port-Bereich) **eine Zeile**
- Gleiches Ziel, Port 80 und 443 → 2 Zeilen

### Mehrere Ziele pro Rolle

- **Mehrere Zeilen**, gleiche `application_name`, `admin_rolle`, `einheit`, `entra_group_name`

---

## Teil 5 – Arbeitsanleitung für den BA-Studenten

### Vorbereitung

1. Öffne `import/excel/Freischaltungen.xlsx`, Blatt **Firewall**
2. Kopiere `import/templates/Freischaltungen-Zielvorlage.csv` nach `import/excel/Freischaltungen-bereinigt.csv`
3. Arbeite **Zeile für Zeile** in der alten Excel – nicht alles auf einmal

### Schritt-für-Schritt pro Freischaltung

1. **Admin Rolle** und **Entra ID - Rollen Name** → Spalten `admin_rolle`, `entra_group_name`
2. **Einheit** → Spalte `einheit` (nur **ein** Wert; bei `MI, SW` → **zwei Zeilen**)
3. **Connector** → Spalte `connector_group` (Liste vom Platform-Team)
4. **application_name** → gleicher Name für alle Zeilen derselben App (Rolle+Einheit+Nr.)
5. **Ziel erkennen:**
   - Enthält `.` und Buchstaben wie `server01.firma.de` → **FQDN**
   - `10.x.x.x/24` → **CIDR**
   - `10.1.1.1 - 10.1.1.50` → **IP-Range**
   - Nur `10.1.1.1` → **Einzel-IP**
6. **FQDN + IP zusammen?** → Nur FQDN eintragen, IP in `source_reference` lassen
7. **Port:** Nur Zahlen. `3389` oder Start `5900`, Ende `5905`
8. **Protokoll:** Immer `tcp` oder `udp`. Bei `TCP/UDP` → **zwei Zeilen**
9. **Original** in `source_reference` kopieren
10. Prüfung ok? → `review_status=approved`, `needs_clarification=no`
11. Unklar? → `needs_clarification=yes`, Kommentar schreiben, **nicht** `approved`

### Wann `needs_clarification = yes`?

- Kein Port und nicht erratbar
- Text wie `Alle Netze`, `wird noch ergänzt`
- UNC-Pfad ohne Servername
- NetBIOS ohne FQDN (`RRSGHDL01-MO`)
- Mehr als 5 verschiedene Ports im Freitext ohne Zuordnung
- Einheit `ungültig` oder mehrere Einheiten in einer Zelle

### Richtig vs. falsch

| Falsch | Richtig |
|--------|---------|
| `fqdn=https://jira.firma.de/` | `fqdn=jira.firma.de` |
| FQDN + IP in beiden Spalten | nur `fqdn`, IP nur in `source_reference` |
| `protocol=RDP` | `protocol=tcp`, `port=3389` |
| `port=80.443` | zwei Zeilen: 80 und 443 |
| `einheit=MI, SW` | zwei Zeilen mit MI und SW |
| `review_status=approved` bei Unklarheit | `needs_clarification=yes` |

### Abschluss

```powershell
./scripts/import/Validate-GSAImportWorkbook.ps1 -InputPath ./import/excel/Freischaltungen-bereinigt.csv
```

Erst wenn **0 Fehler** → Übergabe an Platform-Team für YAML-Export.

---

## Teil 6 – Beispielzeilen

Siehe `import/templates/Freischaltungen-Zielvorlage.csv` (Zeilen 2–10).

---

## Teil 7 – Technische Umsetzung im Projekt

### Bereits vorhanden

| Artefakt | Pfad |
|----------|------|
| YAML-Schema | `schemas/private-access-application.schema.json` |
| Legacy-Import (rohe Firewall-Excel) | `scripts/import/Convert-GSAExcelToYaml.ps1` |
| Parser | `scripts/import/Private/ImportParsers.ps1` |
| Mapping-Beispiele | `import/mappings/*.json.example` |

### Neu angelegt

| Artefakt | Pfad |
|----------|------|
| Zielvorlage (CSV) | `import/templates/Freischaltungen-Zielvorlage.csv` |
| Validierung bereinigte Vorlage | `scripts/import/Validate-GSAImportWorkbook.ps1` |
| Diese Dokumentation | `docs/import/freischaltungen-analyse-und-vorlage.md` |

### Mapping alte → neue Excel

| Alt (Firewall) | Neu (Zielvorlage) |
|----------------|-------------------|
| Nr. | `source_nr` |
| Admin Rolle | `admin_rolle` |
| Entra ID - Rollen Name | `entra_group_name` |
| Einheit | `einheit` (1 Wert/Zeile) |
| Ziel | aufgeteilt in `target_type` + fqdn/ip/cidr/range |
| Port | `port`, `port_range_end` |
| Protokoll | `protocol` (normalisiert tcp/udp) |
| Geprüft | `review_status` |

### Nächster Schritt (YAML-Export)

Nach validierter CSV: Erweiterung von `Convert-GSAExcelToYaml.ps1` oder neues Skript `Convert-GSAImportWorkbookToYaml.ps1`, das nur `review_status=approved` liest und pro `application_name` eine YAML unter `import/output/generated/` erzeugt.

---

## Zusammenfassung für Entscheider

| Frage | Antwort |
|-------|---------|
| Excel automatisch 1:1 importieren? | **Nein** – zu viele Sonderfälle (≈85 % brauchen Interpretation) |
| BA bereinigt in Zielvorlage? | **Ja** – schnellster sicherer Weg |
| Eine App pro Rolle? | **Nein** – Waagensysteme sprengt 500-Segment-Limit |
| **Empfohlenes Modell** | **1 App pro Admin-Rolle + Einheit**, viele `destinations` pro YAML |
| FQDN vor IP? | **Ja**, wenn DNS-Name vorhanden und stabil |
