Name: factory-release-gate
Description: Perform the factory pre-release gate and summarize whether the work is ready for human approval.

---

1. Review `AGENTS.md`, `.trae/rules/00-constitution.md`, and `.trae/factory/factory-system.md` before making a release recommendation.
2. Verify that required evidence exists from each applicable upstream stage: intake, discovery, research, plan, implement, review, security, and QA.
3. Verify that review evidence exists, including independent review when available in the active runtime.
4. Verify that security review evidence exists for any security-relevant changed surface.
5. Verify that QA and test evidence exists for the release scope, and hold the gate if any required upstream evidence is missing, incomplete, or inconsistent with the task outcome.
6. List all required human approvals for database changes, deploy, merge, destructive actions, and production changes.
7. Clearly state that Agent or SOLO orchestrates the active session, that task JSON is the authoritative repository-backed persistence for task state, and that factory scripts remain repository-backed operator tooling rather than native Trae state.
8. If any required evidence or approval is missing, mark the gate as not ready.
9. Do not approve or perform database changes, deploys, merges, destructive actions, or production actions without explicit human approval.
10. Output exactly these sections:
    - `Release Readiness`
    - `Evidence Check`
    - `Open Blockers`
    - `Required Human Approvals`
    - `Recommended Next Step`
