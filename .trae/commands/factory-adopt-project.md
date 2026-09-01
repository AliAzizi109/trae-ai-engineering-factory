Name: factory-adopt-project
Description: Preview first, then adopt an existing or empty project with the canonical factory adoption script.

---

1. Use this command for an existing project or an already-created empty target directory.
2. Require the operator to provide `target path` and `project name` before running anything.
3. Accept optional `project summary` when the operator provides it.
4. Treat `scripts/adopt-factory-project.ps1` as the single canonical engine. Do not reimplement or wrap adoption logic inside this command.
5. This command does not self-authorize execution. Require explicit operator approval before moving from preview to apply.
6. Run a check-only preview first with the canonical script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\adopt-factory-project.ps1 -TargetProjectRoot "C:\path\to\target" -ProjectName "Project Name"
```

7. Do not apply changes after preview unless the operator explicitly asks you to proceed.
8. Only after explicit operator approval, run the canonical apply command:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\adopt-factory-project.ps1 -TargetProjectRoot "C:\path\to\target" -ProjectName "Project Name" -Apply
```

9. If the operator also provides a project summary, pass it on the same canonical command line.
10. Preserve non-destructive behavior and do not promise Node, npm, or other tooling unless actually present and verified.
11. Always report:
    - `preview/apply mode`
    - `exact command used`
    - `what was synced/initialized/deferred`
    - `final verdict`
