## Zusammenfassung

Beschreiben Sie kurz die fachliche und technische Änderung an Microsoft Entra Private Access (Desired State).

## betroffene Anwendungen

- [ ] Neue Anwendung(en)
- [ ] Änderung bestehender Anwendung(en)
- [ ] Entfernung / Deaktivierung (siehe Rollback-Abschnitt)

Dateien unter `config/applications/`:

-

## Risiko & Auswirkung

- [ ] Niedrig (z. B. Metadaten, Tags, Beschreibung)
- [ ] Mittel (Segmente, Ports, Protokolle)
- [ ] Hoch (Zuweisungen, Connector Group, Namen / Identitäten)

## Validierung

- [ ] Lokal `pwsh ./scripts/validate/Invoke-GSAValidation.ps1` ausgeführt
- [ ] Keine beabsichtigten Konflikte mit anderen offenen PRs (gleiche Ziele / Ports)

## Genehmigung / CAB

- [ ] Change-Referenz (Ticket / RFC): 

## Rollback

- [ ] Rollback ist ein Revert dieses PRs auf `main` (Standard)
- [ ] Sonstiges (kurz erläutern):

## Checkliste Governance

- [ ] `owners` und `changeReference` sind gesetzt
- [ ] Namenskonvention eingehalten (`metadata.name` / Dateiname)
- [ ] Connector Group existiert im Zielmandanten und ist korrekt benannt

## Reviewer-Hinweise

Bitte prüfen Sie insbesondere:

- Zielhosts (`destinations`) und Überlappungen mit bestehenden Apps
- `assignments` (Least Privilege)
- `connectorGroup` (richtige Isolation / Standort)
