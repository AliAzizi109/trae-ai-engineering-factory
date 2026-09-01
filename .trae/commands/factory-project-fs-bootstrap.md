Name: factory-project-fs-bootstrap
Description: Run the optional project-fs bootstrap follow-up after adoption when it was deferred or skipped.

---

1. Use this command only as a follow-up after factory adoption when optional project-fs bootstrap was previously `deferred` or explicitly `skipped`.
2. Do not imply this step is required for baseline adoption success.
3. Treat `scripts/bootstrap-project-fs.ps1` as the single canonical engine. Do not duplicate bootstrap logic inside this command.
4. Use the canonical command exactly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-project-fs.ps1
```

5. Report, in order:
   - `exact command used`
   - `whether prerequisites are present`
   - `whether bootstrap completed, was deferred again, or failed`
   - `exact remediation if node or npm.cmd are absent`
6. If `node` or `npm.cmd` are missing, state that optional bootstrap cannot proceed yet. Tell the operator to install Node.js so both commands are available on `PATH`, then rerun the same canonical bootstrap command.
7. Keep the response concise, operator-friendly, and limited to the follow-up bootstrap step.
