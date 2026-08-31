Name: factory-audit
Description: Audit the repository or a requested scope against current factory truth without making changes.

---

1. Read `AGENTS.md`, `.trae/rules/00-constitution.md`, and `.trae/factory/factory-system.md` before inspecting any implementation files.
2. Determine the audit scope from the user request. If no scope is given, audit the full repository at a high level.
3. Inspect only files relevant to the selected scope and compare them against the factory operating model and repository truth.
4. Classify statements and findings with these labels where applicable: `Native Trae`, `Verified Runtime`, `Repository Implementation`, `Workaround`, `Limitation`.
5. Produce a concise audit with exactly these sections:
   - `Findings`
   - `Classification Table`
   - `Target Architecture`
   - `Implementation Plan`
6. In `Findings`, call out concrete gaps, risks, and confirmed alignments.
7. In `Classification Table`, map each important capability or claim to its evidence source and truth label.
8. In `Target Architecture`, describe the desired steady-state behavior that matches the factory documents.
9. In `Implementation Plan`, list advisory next actions in priority order. This plan does not authorize implementation or bypass the normal intake, discovery, research, plan, implement, review, security, QA/test, release gate, and human approval flow.
10. During audit only, do not edit files or perform database changes, deploys, merges, destructive actions, or production actions. If the user asks for implementation, end the audit and start a separate implementation workflow with the required approvals.
