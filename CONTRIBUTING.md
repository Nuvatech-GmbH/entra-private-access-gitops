# CONTRIBUTING

## Ziel

Jeder Beitrag soll die **Produktionsreife** des Repos erhöhen: klare Reviews, nachvollziehbare Changes und minimale Drift zwischen Git und Microsoft Entra.

## Branch-Strategie

- Von `main` abzweigen.
- Kurzlebige Feature-Branches, schnelles Rebase bei Konflikten in `config/applications/`.

## Pull Requests

- PR-Vorlage vollständig ausfüllen.
- Für `config/applications/**` gelten **zwei** Genehmigungen (siehe interne Policy / CODEOWNERS).
- Keine Secrets, keine Tokens, keine `.pfx` Dateien.

## Qualität vor Merge

Lokal ausführen:

```powershell
pwsh ./build/Invoke-LocalCI.ps1
```

## Naming

- `metadata.name` beginnt mit `PA-` und ist eindeutig.
- Dateiname sollte dem Namen entsprechen (Warnung bei Abweichung).

## Review-Leitlinien

- **Security**: Ports minimal halten, Wildcards begründen, Zuweisungen auf Gruppen statt Einzeluser bevorzugen.
- **Betrieb**: Connector Group korrekt? Gibt es Überschneidungen mit anderen Apps?

## GitHub Empfehlungen (Branch Protection)

- `main`: Require PR, Require status checks (`validation` Workflow), Require linear history optional.
- `CODEOWNERS` erzwingen.
- `merge_queue` für `config/applications/**` erwägen.

## Notfall

Siehe `docs/operations/runbook.md`.
