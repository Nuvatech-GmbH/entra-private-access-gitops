# Arbeitsanweisung: Freischaltungen bereinigen (BA-Student)

## Deine Aufgabe in einem Satz

Du überträgst die Freischaltungen aus der **alten Excel** (`Freischaltungen.xlsx`, Blatt **Firewall**) in die **neue Zielvorlage** (`Freischaltungen-Zielvorlage.csv`) – **sauber, eindeutig, eine Zeile = ein Ziel**.

Die bereinigte Datei wird danach **automatisch** in Entra Private Access übernommen. Du musst **keinen App-Namen** erfinden und **keine IDs** vergeben.

---

## Was du brauchst

| Datei | Zweck |
|-------|--------|
| `import/excel/Freischaltungen.xlsx` | Quelle (Blatt **Firewall**) |
| `import/templates/Freischaltungen-Zielvorlage.csv` | Vorlage – kopieren nach `Freischaltungen-bereinigt.csv` |
| Connector-Liste vom Platform-Team | Spalte `connector_group` |

---

## Die wichtigste Regel

### Eine Zeile = genau ein Ziel + Protokoll + Port(s)

| Situation | Was du machst |
|-----------|---------------|
| Mehrere **Ziele** in einer Zelle (IPs/FQDNs mit `/` oder `,`) | **Mehrere Zeilen** (je Ziel eine) – gleiche `ports`-Spalte kannst du kopieren |
| Mehrere **Ports** (443, 4431, 6443, 21, 22, 83) | **Eine Zeile** – in `ports` **kommagetrennt** eintragen |
| Port-**Bereich** (5900–5905) | In `ports` als `5900-5905` (Bindestrich) |
| **TCP und UDP** für **dasselbe** Ziel + gleiche Ports | **Eine Zeile** mit `protocol=both` |
| RDP **und** VNC auf **demselben** Server | **Zwei Zeilen** (3389/tcp und 5900–5905/udp) – unterschiedliches Protokoll |

---

## Spalten – was du ausfüllst

| Spalte | Was eintragen? | Woher? |
|--------|----------------|--------|
| **admin_rolle** | Name der Admin-Rolle | Firewall → „Admin Rolle“ (1:1 übernehmen) |
| **entra_group_name** | Langer Name mit `EIT_PA_Admin_…` | Firewall → „Entra ID - Rollen Name“ (**exakt kopieren**, nichts erfinden) |
| **connector_group** | Connector-Name | Aus der Connector-Liste (z. B. `Office-Gersthofen`) |
| **target_type** | Art des Ziels | Siehe Tabelle unten |
| **fqdn** | Hostname | Nur bei `target_type=fqdn` oder `dnsSuffix` |
| **ip_address** | Einzel-IP | Nur bei `target_type=ipAddress` |
| **cidr_range** | Netz mit /xx | Nur bei `target_type=ipRangeCidr` |
| **ip_range_start** / **ip_range_end** | Von-IP / Bis-IP | Nur bei `target_type=ipRange` |
| **protocol** | `tcp`, `udp` oder **`both`** | Siehe Entscheidungshilfe unten |
| **ports** | Ein Port, mehrere Ports oder Bereich | `3389` oder `443,4431,6443,21,22,83` oder `5900-5905` |
| **source_reference** | Originaltext | Ziel-Zelle aus alter Excel (zum Nachvollziehen) |
| **review_status** | `approved` oder `needs_clarification` | Siehe unten |
| **needs_clarification** | `yes` oder `no` | `yes` = du bist unsicher |
| **review_comment** | Kurzer Hinweis | Pflicht wenn `needs_clarification=yes` |

**Nicht ausfüllen / gibt es nicht:** App-Name, Description, IDs.

---

## target_type – welches Ziel ist es?

| In der alten Excel steht … | target_type | Welche Spalte befüllen? |
|----------------------------|-------------|-------------------------|
| `server01.firma.de` | **fqdn** | `fqdn` |
| `https://jira.firma.de/…` | **fqdn** | `fqdn` = nur `jira.firma.de` (ohne https://) |
| `10.1.2.3` (nur eine IP) | **ipAddress** | `ip_address` |
| `10.61.216.0/24` | **ipRangeCidr** | `cidr_range` |
| `10.0.3.10` bis `10.0.3.20` | **ipRange** | `ip_range_start` + `ip_range_end` |

**Alle anderen Ziel-Spalten leer lassen** – nur die passenden zum `target_type` ausfüllen.

---

## Protokoll: tcp, udp oder both?

Private Access kann **tcp und udp** für dasselbe Ziel – intern als **zwei Segmente**.  
Du schreibst **eine Zeile** mit `protocol=both`; die Automatisierung erzeugt tcp + udp.

| In alter Excel steht … | protocol eintragen |
|------------------------|-------------------|
| `TCP/UDP` | **both** |
| `TCP` oder **leer** | **tcp** |
| `UDP` | **udp** |
| `RDP`, `HTTPS`, `SSH`, `SQL` … | **tcp** (+ passenden Port) |
| SNMP, NTP, TFTP (klar UDP) | **udp** |
| Gar nichts erkennbar | **both** (Standard im Zweifel) |

**Nicht eintragen:** `RDP`, `HTTPS`, `TCP/UDP` als Text – nur `tcp`, `udp` oder `both`.

---

## Die wichtigsten Regeln

1. **FQDN und IP zusammen?** → Nur **FQDN** eintragen. IP nur in `source_reference`.

2. **Mehrzeilige Zelle?** → Jede Zeile = **eine CSV-Zeile**.

3. **Mehrere IPs/CIDRs kommagetrennt?** → **Eine Zeile pro IP/CIDR**.

4. **Mehrere Ports** (80, 443) → **eine Zeile**, `ports=80,443` (kommagetrennt).

5. **Gleiche Rolle + Connector** → `admin_rolle`, `entra_group_name`, `connector_group` in jeder Zeile gleich.

6. **Unklar?** → `needs_clarification=yes`, **nicht** `approved`.

---

## Wann `needs_clarification = yes`?

- Port fehlt und ist nicht sicher ableitbar  
- Text wie „Alle Netze“, „wird noch ergänzt“, „Standardport“  
- Nur NetBIOS-Name ohne FQDN (`SERVER01`)  
- UNC-Pfad (`\\server\freigabe`) ohne klares Ziel  
- Du bist unsicher, ob FQDN oder IP richtig ist  

→ Kommentar schreiben, was fehlt oder wer helfen muss.

---

## Richtig vs. falsch (Kurz)

| Falsch | Richtig |
|--------|---------|
| `fqdn=https://ipam.rs.edeka.net/ui/` | `fqdn=ipam.rs.edeka.net` |
| FQDN **und** IP in fqdn + ip_address | nur `fqdn`, IP in `source_reference` |
| `protocol=RDP` | `protocol=tcp`, `ports=3389` |
| `ports=80.443` | `ports=80,443` (Komma, kein Punkt) |
| 5 IPs und 6 Ports in **einer** Zeile | **5 Zeilen** (je IP eine), `ports` gleich kopieren – **nicht** 30 Zeilen |
| Alles in eine Zeile | aufteilen – **eine Zeile pro Ziel** (Ports dürfen mehrere sein) |
| Unklar, trotzdem `approved` | `needs_clarification=yes` |

---

## Ablauf – Schritt für Schritt

1. Vorlage kopieren → `Freischaltungen-bereinigt.csv`  
2. Blatt **Firewall** öffnen  
3. **Zeile für Zeile** durchgehen (bei zusammengeführten Zellen: Werte von oben mitnehmen)  
4. Pro erkanntem Ziel eine **neue Zeile** in der CSV anlegen  
5. Am Ende prüfen lassen:
   ```powershell
   ./scripts/import/Validate-GSAImportWorkbook.ps1 -InputPath ./import/excel/Freischaltungen-bereinigt.csv
   ```
6. Erst bei **0 Fehlern** → Datei an Platform-Team abgeben  

---

## Mini-Beispiel

**Alte Excel (eine Zelle):**
```
viwsw-ts02.sw.edeka.net (10.80.0.74)
Port: 3389
Protokoll: TCP
Admin Rolle: Medientechnik
Entra ID - Rollen Name: EIT_PA_Admin_DAIS_…_Medientechnik
```

**Neue Zielvorlage (eine Zeile):**

| admin_rolle | entra_group_name | connector_group | target_type | fqdn | protocol | ports | source_reference | review_status | needs_clarification |
|-------------|------------------|-----------------|-------------|------|----------|-------|------------------|---------------|---------------------|
| Medientechnik | EIT_PA_Admin_… | Office-Gersthofen | fqdn | viwsw-ts02.sw.edeka.net | tcp | 3389 | viwsw-ts02… (10.80.0.74) | approved | no |

---

## Bei Fragen

- **entra_group_name** immer aus Firewall/Tab „Rollen und Berechtigung“ – **nicht selbst zusammenbauen**  
- **connector_group** aus der Liste vom Platform-Team  
- Im Zweifel: **`needs_clarification=yes`** statt raten  

Beispiele findest du in `import/templates/Freischaltungen-Zielvorlage.csv`.
