Name: factory-new-project
Description: Start a brand-new project with the canonical factory adoption script.

---

1. Use this command only for a brand-new target path that is missing or empty.
2. Require the operator to provide `target path` before running anything.
3. Accept optional `project name` and `project summary` when the operator provides them.
4. Treat `scripts/adopt-factory-project.ps1` as the single canonical engine. Do not reimplement or wrap adoption logic inside this command.
5. Do not assume this command self-authorizes execution. Confirm the operator-provided target path before running the script.
6. Use the canonical new-project startup path:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\adopt-factory-project.ps1 -TargetProjectRoot "C:\path\to\target" -NewProject
```

7. If the operator also provides a project name and/or project summary, extend the same canonical command pattern truthfully:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\adopt-factory-project.ps1 -TargetProjectRoot "C:\path\to\target" -NewProject -ProjectName "Project Name" -ProjectSummary "Short summary"
```

8. Preserve non-destructive behavior and do not promise Node, npm, or other tooling unless actually present and verified.
9. Always report:
   - `exact command used`
   - `whether startup succeeded`
   - `deferred optional bootstrap` or any required follow-up
   - `final verdict`
