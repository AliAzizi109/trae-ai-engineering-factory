# Trae Factory Test
> Project summary: Reusable Trae-based factory baseline for initializing new repositories with less manual setup.

## What This Repository Is

This repository is a small, reusable baseline for running an AI engineering factory inside a Trae workspace. It keeps the operating rules, agent setup guidance, project-level MCP wiring, and bootstrap scripts in version control, plus a minimal Python proof-of-concept test under `test_poc/`.

## Why It Exists / Benefits

- Moves critical factory behavior into the repository instead of keeping it on one machine.
- Makes new-machine setup reproducible with one bootstrap entrypoint.
- Preserves a disciplined workflow: research, plan, implementation, review, testing, and human approval.
- Separates tracked baseline files from machine-local artifacts.

## V3 Operations

- `scripts/get-factory-operator-status.ps1` gives a quick repo-level dashboard with active/latest task selection, blockers, gates, approval need, and open/blocked/awaiting-approval counts.
- `scripts/get-factory-task-summary.ps1` normalizes older or variant task JSON records and exposes operator-derived fields such as gate status, blocker state, latest event, and latest model attempt.
- `scripts/update-factory-task.ps1` normalizes legacy task state before validation/write and auto-logs major phase, role, model, fallback, blocker, and gate transitions.
- `scripts/select-factory-model.ps1` includes selection index, remaining candidates, the next fallback candidate, and an operator summary while keeping the routing truthfulness note explicit.
- The V2 hardening model remains in place: task-path scope checks, exact handle validation, and synchronized backup guards are preserved or strengthened rather than replaced.

## Repository Structure

```text
.
|- AGENTS.md
|- .trae/
|  |- agents/
|  |  |- factory-reviewer.md
|  |  |- qa-verifier.md
|  |  `- security-reviewer.md
|  |- agent-specs.md
|  |- current-project-state.md
|  |- factory/
|  |  |- config/
|  |  |  |- handoffs.json
|  |  |  |- model-routing.json
|  |  |  `- role-system.json
|  |  |- factory-system.md
|  |  |- verification-matrix.md
|  |  |- tasks/
|  |  |  `- README.md
|  |  `- templates/
|  |     |- task-state.template.json
|  |     `- task.md
|  |- mcp.json
|  `- rules/
|     `- 00-constitution.md
|- .trae-local/
|  `- mcp/
|     `- project-fs/
|        |- package.json
|        `- package-lock.json
|- scripts/
|  |- bootstrap-factory.ps1
|  |- bootstrap-project-fs.ps1
|  |- get-factory-operator-status.ps1
|  |- get-factory-task-summary.ps1
|  |- initialize-factory-project.ps1
|  |- new-factory-task.ps1
|  |- select-factory-model.ps1
|  `- update-factory-task.ps1
`- test_poc/
   `- test_calc.py
```

## Factory Baseline Files

The following tracked files define the reusable factory baseline:

- `AGENTS.md`: repository-level operating model, workflow, roles, and safety expectations.
- `.trae/rules/00-constitution.md`: the authoritative factory constitution and required pipeline.
- `.trae/agents/*.md`: native project subagents with least-privilege tool scopes for review, security review, and verification.
- `.trae/agent-specs.md`: manual setup specifications for custom agents such as `Coder` and `CodeReviewer`.
- `.trae/current-project-state.md`: current baseline status, scope, local-artifact policy, and open items.
- `.trae/factory/config/*.json`: role contracts, model routing, and explicit handoff contracts for the V2 operating model.
- `.trae/factory/factory-system.md`: concise architecture, workflow, security, state, limitation, and recovery notes.
- `.trae/factory/verification-matrix.md`: capability matrix plus a reusable verification-results template.
- `.trae/factory/tasks/README.md`: task-state tracking model for persistent task records.
- `.trae/factory/templates/task-state.template.json`: authoritative V2 task-state template.
- `.trae/factory/templates/task.md`: tracked template for individual task records.
- `.trae/mcp.json`: project-scoped MCP configuration that points the filesystem server at the current workspace.
- `scripts/bootstrap-factory.ps1`: the main entrypoint; validates the baseline and then bootstraps local MCP dependencies.
- `scripts/bootstrap-project-fs.ps1`: installs the local project-fs MCP dependencies deterministically with `npm ci`.
- `scripts/initialize-factory-project.ps1`: applies the initial project identity to a repository created from this baseline and skips README reshaping when a repo already uses a project-specific identity header.
- `scripts/new-factory-task.ps1`: creates a new authoritative JSON task record with a generated Task ID.
- `scripts/update-factory-task.ps1`: updates the authoritative JSON task record safely.
- `scripts/get-factory-task-summary.ps1`: prints an operational summary for one task record.
- `scripts/select-factory-model.ps1`: picks the preferred or next fallback model for a role from the tracked routing source.
- `.trae-local/mcp/project-fs/package.json` and `package-lock.json`: tracked dependency manifests required to recreate the local MCP install.
- `.gitignore`: excludes machine-local files and install outputs from Git.

## Local-Only Artifacts

These artifacts should stay local to a machine or session and should not be committed:

- `.trae-local/mcp/project-fs/node_modules/`
- `.trae-local/mcp/project-fs/npm-debug.log*`
- `chat-*.txt`
- `debug-mcp-routing-error.md`
- `.dbg/`

Note: `.trae-local/mcp/project-fs/package.json` and `package-lock.json` are tracked baseline files; only the installed outputs in that area are local-only.

## Prerequisites

- Windows with PowerShell
- Git
- Node.js and npm available on `PATH`
- Trae / Trae Ultra workspace support
- Python if you want to run the sample test module
- `pytest` if you want to execute `test_poc/test_calc.py`

## Installation / Bootstrap On a New Machine

1. Clone the repository.
2. Open the repository in Trae.
3. Enable Project MCP in Trae settings for this workspace if it is not already enabled.
4. If you want native project subagents, enable the Subagents Directory feature in Trae and let the workspace load `.trae/agents/`.
5. Prefer the native project subagents under `.trae/agents/` when Trae exposes them in the workspace.
6. Create or verify the `Coder` and `CodeReviewer` custom agents from `.trae/agent-specs.md` only when native project subagents are unavailable or you still need the manual fallback.
7. Run the single bootstrap entrypoint:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-factory.ps1
```

What it does:

- Validates that the tracked factory baseline files exist.
- Runs `scripts/bootstrap-project-fs.ps1` if validation passes.
- Installs the local filesystem MCP dependencies from the tracked manifests.

To validate the baseline without installing anything, use check-only mode:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-factory.ps1 -CheckOnly
```

`-CheckOnly` verifies that the required baseline files are present and then exits successfully without running `npm ci`.

Note: if Trae's local toolhost prints extra PowerShell execution-policy noise
after the success lines above, treat the bootstrap as successful as long as the
explicit factory success messages were printed.

Truth note:

- Built-in `coder` and `code-reviewer` are the most reliable verified runtime-callable specialist roles in this environment.
- Repository-defined `.trae/agents/*` are useful tracked implementations, but should not be claimed as runtime-callable unless that behavior is verified in the active workspace.
- Repository-backed task JSON is a durable workaround, not native Trae runtime state.

## Starting a New Project From This Baseline

This repository can also be used as a reusable factory baseline for a new project. After cloning or creating a new repository from this baseline, run the initializer before starting the actual project work:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\initialize-factory-project.ps1 -ProjectName "My Project" -ProjectSummary "Short summary"
```

To preview the planned identity updates without modifying any files:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\initialize-factory-project.ps1 -ProjectName "My Project" -ProjectSummary "Short summary" -CheckOnly
```

Initializer behavior notes:

- The initializer updates `README.md` only when the repository still uses the baseline identity-header structure from this baseline.
- An adopted repository may keep its own project-specific `README.md`; in that case the initializer skips the README change instead of reshaping it on every run.
- `.trae/current-project-state.md` still receives the current project identity so the tracked factory state stays aligned with the repository adoption.

## Important Commands

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-factory.ps1
```
Runs the full baseline validation and local project-fs bootstrap.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-factory.ps1 -CheckOnly
```
Checks whether the repository contains the required tracked baseline files without installing dependencies.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-project-fs.ps1
```
Reinstalls only the local project-fs MCP dependencies from the tracked lockfile.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\initialize-factory-project.ps1 -ProjectName "My Project" -ProjectSummary "Short summary"
```
Applies the initial repository identity to `README.md` and `.trae/current-project-state.md` for a new project created from this baseline.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-factory-task.ps1 -Objective "Upgrade factory baseline"
```
Creates a persistent JSON task record under `.trae/factory/tasks/` from the tracked template.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\select-factory-model.ps1 -Role coder_implementer
```
Selects the preferred or next fallback model for one role from the tracked routing config.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\get-factory-task-summary.ps1 -TaskPath ".trae\factory\tasks\task-id.json"
```
Prints a concise operational summary for one task record.

```powershell
git status
```
Shows tracked, modified, and untracked files before sync, staging, or review.

```powershell
python -m pytest .\test_poc\test_calc.py
```
Runs the small Python proof-of-concept test, if Python and `pytest` are available.

## Docs Portability

- Active, day-to-day operating documents should use repository-relative links instead of machine-specific `file:///` paths.
- Historical or archive documents that still contain old `file:///` links should not be mass-rewritten automatically.
- Fix an old machine-specific link when that document becomes an active entrypoint or a daily operating reference again.

## Daily Workflow

1. Pull or sync the current branch from GitHub when it is safe to do so.
2. Run the bootstrap command on a new machine, or rerun it if local MCP dependencies are missing.
3. Prefer the native project subagents under `.trae/agents/`; use `.trae/agent-specs.md` only as the documented manual fallback.
4. Create or update a task record in `.trae/factory/tasks/` for persistent state when work spans multiple steps.
5. Work through the required flow: Intake -> Discovery -> Research -> Plan -> Implement -> Review -> Security -> QA/Test -> Human approval.
6. Run the relevant checks for the files you changed.
7. Review `git status` and stage only the intended files.
8. Commit, push, merge, or deploy only when the human explicitly approves.

## Safety Rules

- Do not skip review or tests for feature/fix work.
- Do not deploy, merge, or run destructive commands without explicit human approval.
- Treat `.trae/rules/00-constitution.md` as authoritative.
- Prefer staging only the intended files; avoid broad staging by default.
- Keep machine-local artifacts out of Git.

## Notes About GitHub Sync / Multi-Device Usage

- GitHub is the source of truth for the tracked factory baseline across devices.
- A fresh clone on another machine should only need the tracked files plus the bootstrap command above.
- `.trae/mcp.json` uses `${workspaceFolder}`, so the workspace can live in different filesystem locations on different machines.
- Native project subagents travel with the repository; recreate or verify the manual fallback agents from `.trae/agent-specs.md` only when account-level agent state is missing or native support is unavailable.
- Native project subagent routing still depends on the active Trae workspace supporting the Subagents Directory feature.
- MCP portability is configuration-level portability; live MCP access remains scoped to the currently active workspace.
- Commit tracked baseline changes; do not sync local dependency installs or session/debug artifacts.
- The current bootstrap flow is Windows-first because the local install script resolves `npm.cmd` from PowerShell.
