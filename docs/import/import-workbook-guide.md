# Import-Arbeitsbuch – Anleitung

## Ziel

Firewall- oder Freigabelisten werden in ein standardisiertes CSV-Arbeitsbuch überführt. Die Datei wird validiert und anschließend in Private-Access-YAML exportiert.

**Eine Zeile = ein Ziel + Protokoll + Port(s).** App-Namen und IDs werden automatisch abgeleitet.

---

## Dateien

| Datei | Zweck |
|-------|--------|
| Quelldaten (Excel/CSV) | `import/excel/` (lokal, nicht im Repository) |
| Arbeitsbuch-Vorlage | `import/templates/import-workbook-template.csv` |
| Bereinigtes Arbeitsbuch | z. B. `import/excel/access-rules.csv` |

---

## Regeln

| Situation | Vorgehen |
|-----------|----------|
| Mehrere Ziele in einer Zelle | Eine Zeile pro Ziel; `ports` kann kopiert werden |
| Mehrere Ports | Eine Zeile, `ports` kommagetrennt (z. B. `443,8080`) |
| Port-Bereich | `5900-5905` in `ports` |
| TCP und UDP, gleiches Ziel | `protocol=both` |
| Unklare Angaben | `needs_clarification=yes`, nicht `approved` |

---

## Spalten

| Spalte | Beschreibung |
|--------|--------------|
| `admin_rolle` | Fachliche Rolle / Verantwortungsbereich |
| `entra_group_name` | Entra-Gruppe für die Zuweisung (exakt aus Identity-Quelle) |
| `connector_group` | Name der Connector Group im Mandanten |
| `target_type` | `fqdn`, `ipAddress`, `ipRangeCidr`, `ipRange`, `dnsSuffix` |
| `fqdn` / `ip_address` / `cidr_range` / `ip_range_*` | Je nach `target_type` |
| `protocol` | `tcp`, `udp` oder `both` |
| `ports` | Einzelport, Liste oder Bereich |
| `source_reference` | Originaltext zur Nachverfolgung |
| `review_status` | `approved`, `needs_clarification`, `pending`, `rejected` |
| `needs_clarification` | `yes` oder `no` |
| `review_comment` | Pflicht bei `needs_clarification=yes` |

---

## Validierung

```powershell
./scripts/import/Validate-GSAImportWorkbook.ps1 -InputPath ./import/excel/access-rules.csv
```

Bei **0 Fehlern** kann der Export in YAML erfolgen.

Beispiele: `import/templates/import-workbook-template.csv`
