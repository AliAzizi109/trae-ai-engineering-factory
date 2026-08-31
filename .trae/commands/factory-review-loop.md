Name: factory-review-loop
Description: Run the factory post-change review loop with independent review, security review when relevant, and QA evidence before any completion claim.

---

1. Start only after implementation changes exist.
2. Review `AGENTS.md`, `.trae/rules/00-constitution.md`, and `.trae/factory/factory-system.md` before judging completion.
3. Require an independent code review using the project `code-reviewer` path when available in the active runtime. If it is not available, state that limitation and perform the best available review path without mislabeling it as independent.
4. Add a security review whenever changed files affect auth, permissions, secrets, external interfaces, data handling, CI/CD, release flow, or other sensitive surfaces.
5. Run targeted QA and test verification for the changed scope and collect concrete evidence.
6. Treat `FAIL` as critical or high severity issues only. Record lower-severity notes separately without blocking `PASS`.
7. If review or QA returns `FAIL`, remediate the blocking issues using the project `coder` path when available in the active runtime, but stop and require explicit human approval before any database change, deploy, merge, destructive action, or production action. If remediation changes a security-relevant surface, run a fresh security review before a final `PASS`. Then repeat the loop.
8. Stop after 3 total review loops. If still failing, output an escalation report with blocking issues, attempted fixes, remaining risks, and required human decisions.
9. Treat any completion wording as provisional until the release gate is satisfied when applicable. No final done, completed, or closed claim is valid before required release-gate conditions are met and any required human approval is obtained.
10. Report the final result with:
    - `Review Verdict`
    - `Security Verdict` if applicable
    - `QA/Test Evidence`
    - `Non-Blocking Notes`
    - `Blocking Issues`
    - `Next Action`
