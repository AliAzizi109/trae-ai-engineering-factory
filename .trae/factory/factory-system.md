# Factory System

## Architecture

- Built-in `Agent` is the main orchestrator when Trae exposes native project subagents in the active workspace.
- `AGENTS.md` defines the repository operating model.
- `.trae/rules/00-constitution.md` remains the authoritative workflow and safety policy.
- `.trae/agents/` stores native project subagents with least-privilege tool scopes.
- `.trae/agent-specs.md` keeps the manual `Coder` and `CodeReviewer` fallback setup when native subagents are unavailable.
- `.trae/factory/config/role-system.json` is the V2 source of truth for role contracts.
- `.trae/factory/config/model-routing.json` is the V2 source of truth for model routing and failover.
- `.trae/factory/config/handoffs.json` is the V2 source of truth for phase-to-phase contracts.
- `.trae/factory/tasks/` stores persistent task records created from `.trae/factory/templates/task-state.template.json`.

## Workflow

- Standard flow remains Research -> Plan -> Implement -> Review -> Test -> Human approval, with V2 handoff subphases such as security review, QA, and release gating tracked explicitly in task state.
- Prefer native project subagents when Trae exposes them in the repository and the Subagents Directory feature is enabled.
- Use the manual `Coder` and `CodeReviewer` setup only as a documented fallback.
- Keep long-running work tied to a task record instead of relying on chat context alone.
- If review, security, or QA fails, loop back through implementation when it is safe to do so.

## Security

- `factory-reviewer` and `security-reviewer` are read-only by design.
- Security review stays separate from implementation.
- `qa-verifier` can run checks but is still non-editing.
- Human approval is still required before commit, push, merge, deploy, or destructive actions.

## State

- Long-lived task state is stored as repository-backed JSON under `.trae/factory/tasks/`.
- The V1 markdown task template remains readable for historical continuity, but V2 authoritative state is JSON.
- Each task records objective, scope, constraints, priority, current phase, current role, current model, fallback usage, findings, review, security, QA, retries, blockers, next automatic action, escalation, verification summary, and final outcome.
- `.trae/current-project-state.md` tracks the current baseline status at project level.
- `scripts/new-factory-task.ps1` initializes a tracked task record with a generated Task ID.
- `scripts/update-factory-task.ps1` adds V3 normalization and auto-events without weakening the task-path guard, handle validation, or synchronized backup guard.
- `scripts/get-factory-task-summary.ps1` prints a concise operational status for one task with normalized V3 operator fields on top of the same hardening model.
- `scripts/get-factory-operator-status.ps1` prints an operator dashboard for the active/latest task or a requested task across the repository.
- `scripts/select-factory-model.ps1` chooses the preferred or next fallback model for a role from the tracked routing source.

## Native vs Fallback

- Native in Trae: the top-level Agent experience, project-scoped MCP configuration, and human confirmation points when the active Trae environment provides them.
- Repository implementation: `.trae/agents/`, tracked configs, tracked handoff contracts, tracked scripts, and tracked task-state templates.
- Workaround in this baseline: repository-backed task-state durability and orchestrator-managed role phases that do not have a distinct verified runtime agent.

## Limitations

- Native project subagent behavior depends on Trae support in the current workspace and the Beta switch that enables the Subagents Directory.
- Manual custom agents are still required where native project subagents are unavailable.
- MCP access is scoped to the active workspace at runtime; portable config does not mean a single live session can access every project simultaneously.
- Windows sandbox support in Trae is still limited compared with macOS and remote Linux, so OS-level isolation is not fully native on Windows yet.
- Repository-defined `.trae/agents/*` should not be described as verified runtime-callable unless that behavior is directly proven in the active workspace.
- Nested child-to-child delegation is not treated as available unless proven in the active runtime.

## Recovery

- Re-run `scripts/bootstrap-factory.ps1 -CheckOnly` to confirm the tracked baseline still exists.
- Recreate missing task files from the JSON template when needed.
- Re-open the latest relevant task record under `.trae/factory/tasks/` plus `.trae/current-project-state.md` before resuming a broken session.
- Use `scripts/get-factory-operator-status.ps1` for the fastest repo-level operational dashboard.
- Use `scripts/update-factory-task.ps1` to checkpoint current role, model, fallback usage, findings, events, verification summary, and next automatic action instead of relying on chat memory.
- If native subagents are unavailable, fall back to the manual agent specs in `.trae/agent-specs.md`.
