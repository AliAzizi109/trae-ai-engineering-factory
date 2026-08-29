# Factory System

## Architecture

- Built-in `Agent` is the main orchestrator when Trae exposes native project subagents in the active workspace.
- `AGENTS.md` defines the repository operating model.
- `.trae/rules/00-constitution.md` remains the authoritative workflow and safety policy.
- `.trae/agents/` stores native project subagents with least-privilege tool scopes.
- `.trae/agent-specs.md` keeps the manual `Coder` and `CodeReviewer` fallback setup when native subagents are unavailable.
- `.trae/factory/tasks/` stores persistent task records created from `.trae/factory/templates/task.md`.

## Workflow

- Standard flow: Research -> Plan -> Implement -> Review -> Test -> Human approval.
- Prefer native project subagents when Trae exposes them in the repository and the Subagents Directory feature is enabled.
- Use the manual `Coder` and `CodeReviewer` setup only as a documented fallback.
- Keep long-running work tied to a task record instead of relying on chat context alone.

## Security

- `factory-reviewer` and `security-reviewer` are read-only by design.
- Security review stays separate from implementation.
- `qa-verifier` can run checks but is still non-editing.
- Human approval is still required before commit, push, merge, deploy, or destructive actions.

## State

- Long-lived task state is stored as markdown under `.trae/factory/tasks/`.
- Each task records plan, findings, execution log, evidence, retry history, capability classification, review, security, testing, and final approval status.
- `.trae/current-project-state.md` tracks the current baseline status at project level.
- `scripts/new-factory-task.ps1` initializes a tracked task record with a generated Task ID.
- `scripts/update-factory-task.ps1` safely updates supported task fields and appends recovery-oriented bullets to the same record.

## Native vs Fallback

- Native in Trae: project subagent definitions under `.trae/agents/`, built-in `Agent` orchestration, tool-level subagent allowlists, project-scoped MCP configuration, and human confirmation points in the Agent workflow.
- Workaround in this baseline: manual fallback agents documented in `.trae/agent-specs.md`, repository-tracked markdown task state, and verification logs stored in-repo.

## Limitations

- Native project subagent behavior depends on Trae support in the current workspace and the Beta switch that enables the Subagents Directory.
- Manual custom agents are still required where native project subagents are unavailable.
- MCP access is scoped to the active workspace at runtime; portable config does not mean a single live session can access every project simultaneously.
- Windows sandbox support in Trae is still limited compared with macOS and remote Linux, so OS-level isolation is not fully native on Windows yet.
- `scripts/new-factory-task.ps1` creates task files but does not automate review or approvals.
- `scripts/update-factory-task.ps1` is limited to the tracked task record format and does not infer missing workflow decisions.

## Recovery

- Re-run `scripts/bootstrap-factory.ps1 -CheckOnly` to confirm the tracked baseline still exists.
- Recreate missing task files from the template when needed.
- Re-open the latest relevant task record under `.trae/factory/tasks/` plus `.trae/current-project-state.md` before resuming a broken session.
- Use `scripts/update-factory-task.ps1` to checkpoint recovery details into Plan, Execution Log, Evidence, Findings, and Remaining Work instead of relying on chat memory.
- If native subagents are unavailable, fall back to the manual agent specs in `.trae/agent-specs.md`.
