# Import-Arbeitsbuch – Anleitung

## Ziel

Eine **zentrale Excel-Datei** sammelt Freigaben (Jumphosts, DCs, …). Ein Python-Skript erzeugt daraus YAML-Dateien und markiert verarbeitete Zeilen in der Excel als **übernommen**.

**Eine Zeile = ein Ziel + Protokoll + Port(s).** Mehrere Zeilen mit gleichem `application_name` werden zu **einer** YAML-App zusammengefasst.

---

## Dateien

| Datei | Zweck |
| --- | --- |
| **Vorlage (im Repo)** | `import/templates/private-access-import-template.xlsx` |
| **Arbeitsdatei (lokal)** | `import/excel/private-access-import.xlsx` (gitignored) |
| **Export-Skript** | `scripts/import/Convert-ImportWorkbookToYaml.py` |
| **Manifest** | `import/output/import-manifest.json` (gitignored) |
| **YAML-Ziel** | `config/applications/*.yaml` |

---

## Einrichtung (einmalig)

```bash
python3 -m venv import/.venv
source import/.venv/bin/activate   # Windows: import\.venv\Scripts\activate
pip install -r import/requirements.txt
cp import/templates/private-access-import-template.xlsx import/excel/private-access-import.xlsx
```

Vorlage neu erzeugen (optional):

```bash
python3 scripts/import/New-ImportWorkbookTemplate.py
```

---

## Excel ausfüllen

### Eingabe-Spalten

| Spalte | Beschreibung |
| --- | --- |
| `application_name` | Entra-App-Name, z. B. `EIT_PrivateAccess_NST_DCs` |
| `connector_group` | Exakter Name in Entra (Forward-Fill möglich) |
| `entra_group_name` | Zuweisungsgruppe (Forward-Fill möglich) |
| `target_type` | `fqdn`, `ipAddress`, `ipRangeCidr`, `ipRange`, `dnsSuffix` |
| `fqdn` / `ip_address` / … | Je nach `target_type` |
| `protocol` | `tcp`, `udp` oder `both` (= `tcp,udp` in YAML) |
| `ports` | `3389` oder `389,636,88` oder `5900-5905` |
| `change_reference` | Ticket/CHG (optional) |
| `workload` | Tag in YAML, z. B. `jumphosts`, `domain-controllers` |
| `review_status` | Nur `approved` wird importiert |

Leere `application_name` / `connector_group` in Folgezeilen übernehmen den Wert der letzten befüllten Zeile (Forward-Fill).

### Rückmeldung-Spalten (vom Skript gesetzt)

| Spalte | Werte |
| --- | --- |
| `import_status` | `offen` → `übernommen`, `übersprungen` oder `fehler` |
| `generated_yaml` | Dateiname, z. B. `EIT_PrivateAccess_NST_DCs.yaml` |
| `imported_at` | UTC-Zeitstempel des Laufs |
| `import_note` | Kurzinfo (Segmentanzahl oder Fehler) |

---

## Import ausführen

```bash
python3 scripts/import/Convert-ImportWorkbookToYaml.py
```

Optionen:

| Option | Wirkung |
| --- | --- |
| `-i path/to/workbook.xlsx` | Andere Eingabedatei |
| `--dry-run` | Vorschau, nichts schreiben |
| `--regenerate` | Auch bereits `übernommen` Zeilen erneut verarbeiten |
| `--mark-skipped` | Nicht-approved Zeilen als `übersprungen` markieren |

Ablauf:

1. Zeilen mit `review_status=approved` und `import_status=offen` (oder leer) werden gelesen
2. YAMLs nach `config/applications/` geschrieben
3. Excel wird **zurückgeschrieben** – betroffene Zeilen → `import_status=übernommen`
4. PR mit generierten YAMLs + ggf. aktualisierter Excel (lokal behalten, nicht ins Repo committen)

---

## Regeln

| Situation | Vorgehen |
| --- | --- |
| Mehrere Ziele | Eine Zeile pro Ziel |
| TCP + UDP | `protocol=both` |
| Neue Region / App | Neue `application_name`-Gruppe |
| Zeile noch prüfen | `review_status=pending` → wird übersprungen |
| Erneut generieren | `--regenerate` |

---

## Validierung vor PR

```powershell
pwsh ./scripts/validate/Invoke-GSAValidation.ps1
```

---

## Legacy

- Alte CSV-Vorlage: `import/templates/import-workbook-template.csv`
- Jumphost-Einzelimport: `Convert-JumphostsExcelToYaml.py` (ruft neues Skript auf)
