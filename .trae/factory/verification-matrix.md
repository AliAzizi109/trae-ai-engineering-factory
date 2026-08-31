# Verification Matrix

## Repo-Specific Capability Truth

| Capability | Truth Label | Evidence source | Notes |
| --- | --- | --- | --- |
| Built-in Agent orchestration | `Native Trae` | Official Trae docs + runtime use in this environment | Native product capability, bounded by the active runtime surface. |
| Native project subagents | `Native Trae` | Official Trae docs | Native when the active workspace exposes the Subagents Directory feature. |
| Manual fallback agents (`Coder`, `CodeReviewer`) | `Workaround` | `.trae/agent-specs.md` + prior runtime use | Account-level or manual fallback; treat as `Verified Runtime` only when current-environment evidence is explicit. |
| Independent review verdicts | `Verified Runtime` | Runtime `code-reviewer` smoke tests and prior reviews | Clean scopes return `PASS`; blocking findings return `FAIL`. |
| Least-privilege review tools | `Repository Implementation` | Repository subagent prompts + runtime tool registry context | Useful scope control, but not a hard sandbox guarantee by itself. |
| Project-scoped MCP configuration | `Repository Implementation` | Tracked `.trae/mcp.json` | Portable tracked config is not the same as live workspace binding. |
| Persistent task state | `Workaround` | Repository-tracked JSON task files under `.trae/factory/tasks/` | Durable across sessions and devices through Git, but not native Trae durable state. |
| Windows sandbox isolation | `Limitation` | Official Trae security notes | No safe native Windows sandbox guarantee is claimed here. |

## Repo-Specific Notes

- Prefer native project subagents when the active workspace supports them.
- Keep `.trae/agent-specs.md` as documented manual fallback only.
- Use the QA verification skill under `.trae/skills/qa-verification-sop/` for reusable verification procedure and checklist guidance.
- Keep capability claims tied to observed runtime evidence, not only to tracked repository files.

## Evidence Record Template

| Task ID | Scope | Reviewer result | Security result | QA result | Commands / evidence | Remaining gaps |
| --- | --- | --- | --- | --- | --- | --- |
| TASK-YYYYMMDD-HHMMSS | Updated files | PASS / FAIL | PASS / FAIL / N/A | PASS / FAIL / N/A | Exact checks and artifacts | Explicit residual gaps |
