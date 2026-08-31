# Trae AI Engineering Factory
> Project summary: Reusable Trae-based factory baseline for initializing new repositories with less manual setup.

## What This Repository Is

This repository is a reusable baseline for running an AI engineering factory
inside a Trae workspace. It keeps the minimum tracked structure needed for
project rules, repository-tracked integration, persistent task state,
and operator workflows.

## Human Entrypoint

Start here when working with this baseline:

1. Read `AGENTS.md` for thin cross-tool operating rules and capability labels.
2. Read `.trae/rules/00-constitution.md` for the authoritative workflow and
   safety contract.
3. Use `.trae/factory/factory-system.md` when you need the architecture delta
   between native Trae behavior and the factory-only layer.
4. Use `.trae/factory/verification-matrix.md` for repo-specific capability
   truth.

## Prerequisites

Mandatory for baseline adoption and daily script usage:

- Windows with PowerShell
- Git
- Trae workspace support

Optional or deferred:

- Node.js and `npm.cmd` on `PATH` only when you want the local project-fs MCP dependencies bootstrapped automatically
- Python and `pytest` only if you want to run the sample validation test

## Bootstrap Quickstart

On a new machine or fresh clone:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-factory.ps1
```

Validation only:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-factory.ps1 -CheckOnly
```

This validates the tracked baseline and then prepares the local project-fs MCP
installation when not in check-only mode. If `node` or `npm.cmd` are missing,
the baseline remains usable and the project-fs bootstrap is reported as
deferred with an explicit remediation message.

## Project Startup Paths

Use one canonical entrypoint for both startup cases:

`scripts/adopt-factory-project.ps1`

### Brand-New Project Startup

Recommended when the target folder is missing or empty and you want the fastest
template-style start with the factory baseline applied immediately.

Shortest recommended command:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\adopt-factory-project.ps1 -TargetProjectRoot "C:\work\my-new-project" -NewProject
```

New-project startup behavior:

1. Reuses the same baseline sync, project initialization, and optional project-fs bootstrap logic as normal adoption.
2. Applies immediately by design, so no extra `-Apply` flag is needed.
3. Requires the target folder to be missing or empty.
4. Derives `ProjectName` from the target folder name when you do not pass `-ProjectName`.
5. Accepts optional `-ProjectName`, `-ProjectSummary`, and `-SkipOptionalProjectFsBootstrap`.

Example with explicit identity:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\adopt-factory-project.ps1 -TargetProjectRoot "C:\work\my-new-project" -NewProject -ProjectName "My New Project" -ProjectSummary "Short summary"
```

### Existing Or Empty Project Adoption

Recommended when you are adopting into an existing repository, or when you want
the preview-first path before applying changes.

Shortest recommended preview command:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\adopt-factory-project.ps1 -TargetProjectRoot "C:\work\my-project" -ProjectName "My Project"
```

That command is check-only by default. It previews:

- baseline files that would be established or updated
- project-specific files that would be seeded only when missing
- project identity initialization for `README.md` and `.trae/current-project-state.md`
- optional project-fs bootstrap follow-up

Apply the adoption non-destructively after review:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\adopt-factory-project.ps1 -TargetProjectRoot "C:\work\my-project" -ProjectName "My Project" -ProjectSummary "Short summary" -Apply
```

Shared behavior notes:

1. If the target directory does not exist, the apply run creates it safely.
2. Baseline-managed files are synced non-destructively.
3. `README.md` and `.trae/current-project-state.md` are seeded only when missing.
4. Existing adopter-owned `README.md` content is not overwritten silently; the script reports a manual follow-up when automatic identity updates are not safe.
5. Optional project-fs bootstrap runs during apply mode unless `-SkipOptionalProjectFsBootstrap` is used.

When `node` or `npm.cmd` are absent during apply mode, startup or adoption still
completes. The final report marks project-fs bootstrap as `deferred` and tells
the operator to install Node.js so both commands are on `PATH`, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-project-fs.ps1
```

## Operator Quickstart

Create a tracked task quickly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-factory-task.ps1 -Objective "..." -Scope "..." -Constraints "..."
```

Or create a task directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-factory-task.ps1 -Objective "Upgrade factory baseline"
```

Inspect one task:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\get-factory-task-summary.ps1 -TaskPath ".trae\factory\tasks\task-id.json"
```

View the operator dashboard:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\get-factory-operator-status.ps1
```

Preview a baseline sync into an adopter:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-factory-baseline.ps1 -TargetProjectRoot <repo-path>
```

## Runtime Truth Notes

- Built-in Agent behavior is native only where the active Trae runtime exposes
  it.
- Repository-defined `.trae/agents/*` are useful tracked contracts, but should
  not be claimed as runtime-callable unless the active workspace proves that.
- Repository-backed task JSON is a durable factory layer, not native Trae state.
- Project-scoped MCP configuration is portable through the repository, while
  live MCP access still remains scoped to the active workspace.

## Local-Only Artifacts

Keep these local and out of Git:

- `.trae-local/mcp/project-fs/node_modules/`
- `.trae-local/mcp/project-fs/npm-debug.log*`
- `chat-*.txt`
- `debug-mcp-routing-error.md`
- `.dbg/`

## Daily Use

- Run the bootstrap check on new machines or when local MCP dependencies are missing.
- Prefer native project subagents first, then manual fallback only when needed.
- Keep long-running work in tracked task records under `.trae/factory/tasks/`.
- Use the QA verification skill for reusable evidence procedure, and keep repo-specific truth in the verification matrix.
- Commit, push, merge, deploy, or destructive actions only with explicit human approval.
