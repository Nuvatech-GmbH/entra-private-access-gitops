# Roadmap (Vorschlag)

1. **Policy-as-Code**: OPA / Conftest parallel zu JSON Schema für komplexere Regeln (Wildcard-Overlap).
2. **Import-Workflow**: bestehende Apps automatisch in YAML serialisieren (`metadata.graphApplicationId` setzen).
3. **Segment-Deletion Standardisieren**: kontrollierte Löschung abgelaufener Segmente mit explizitem Flag im YAML (`spec.lifecycle.removeAbsentSegments: true`).
4. **Microsoft Entra Workload ID** für Runner außerhalb von GitHub (z. B. Azure DevOps) mit gleicher Modulbasis.
5. **Konfigurierbare App-Rollen** statt nur Default `User` Role (falls Microsoft Graph dies dauerhaft unterstützt).
