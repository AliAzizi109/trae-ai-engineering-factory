Name: factory-adoption-status
Description: Read the outcome of the most recent or specified factory adoption or startup run.

---

1. Use this command only for reading and reporting adoption status. Keep it read-only and do not self-authorize further execution.
2. Accept either the most recent evidenced adoption/startup run or a specific operator-provided run record. If facts are missing, say so plainly.
3. Treat `scripts/adopt-factory-project.ps1` as the canonical adoption engine. Do not reimplement adoption logic inside this command.
4. Report, in order:
   - `startup path used`
   - `exact adoption command used` when known from evidence
   - `whether baseline sync succeeded`
   - `whether project identity initialization succeeded`
   - `whether optional project-fs bootstrap was ready, deferred, skipped, failed, or unknown`
   - `required manual follow-ups`
   - `final operator-facing status`
5. Keep the report concise and truthful. Do not imply that optional project-fs bootstrap is required for baseline adoption success.
6. If the operator asks to remediate a deferred or skipped optional bootstrap state, direct them to `/factory-project-fs-bootstrap`.
