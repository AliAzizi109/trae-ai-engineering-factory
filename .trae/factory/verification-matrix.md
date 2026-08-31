# Verification Matrix

## Capability Matrix

| Capability | Status | Evidence source | Notes |
| --- | --- | --- | --- |
| Built-in Agent orchestration | Supported but limited | Official Trae docs + runtime use of delegated agents in this environment | Native in Trae, but direct end-to-end UI automation is outside this API surface. |
| Native project subagents | Supported but limited | Official Trae docs | Requires Subagents Directory feature in the active Trae workspace. |
| Manual fallback agents (`Coder`, `CodeReviewer`) | Confirmed | Existing baseline files + prior runtime reviews | Account-level setup is still manual when native subagents are unavailable. |
| Independent review verdicts | Confirmed | Runtime `code-reviewer` smoke tests and prior reviews | Blocking findings return `FAIL`, clean scope returns `PASS`. |
| Least-privilege review tools | Confirmed | Runtime tool registry + repository subagent frontmatter | Prompt rules alone are not treated as hard security boundaries. |
| Project-scoped MCP configuration | Confirmed | Tracked `.trae/mcp.json` + runtime `project-fs` read test | Runtime access stays bound to the active workspace. |
| Persistent task state | Workaround | Repository-tracked JSON task files under `.trae/factory/tasks/` | Not a native Trae state store, but durable across sessions and devices through Git. |
| Windows sandbox isolation | Not available | Official Trae security blog | Windows support is still limited compared with macOS / remote Linux. |

## Notes

- Native project subagents are preferred when Trae supports them in the repository.
- `Coder` and `CodeReviewer` remain supported as manual fallback agents.
- Built-in `coder` and `code-reviewer` are the most reliable verified runtime-callable specialist roles in this environment.
- Verification scope should stay limited to the files changed for the current task.
- Mark each test with concrete evidence instead of implied success.
- QA terminal verdicts should include structured `qa_verification` evidence:
  blocking checks, advisory checks, passed, failed, skipped, not-possible,
  commands, artifacts, invocation path, and evidence sufficiency.

## Test Results Template

| Task ID | Scope | Reviewer result | Security result | QA result | Commands / evidence | Remaining gaps |
| --- | --- | --- | --- | --- | --- | --- |
| TASK-YYYYMMDD-HHMMSS | Updated files | PASS / FAIL | PASS / FAIL / N/A | PASS / FAIL / N/A | List exact checks and runtime evidence | List unresolved items |
