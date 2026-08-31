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

- Windows with PowerShell
- Git
- Node.js and npm on `PATH`
- Trae workspace support
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
installation when not in check-only mode.

## Adoption Overview

This repository can be used as a baseline for a new project.

1. Clone the repository and open it in Trae.
2. Enable Project MCP for the workspace when needed.
3. If the active workspace supports native project subagents, let it load
   `.trae/agents/` and prefer that path.
4. Use `.trae/agent-specs.md` only when you still need manual fallback setup
   for `Coder` or `CodeReviewer`.
5. Initialize the adopter repository identity:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\initialize-factory-project.ps1 -ProjectName "My Project" -ProjectSummary "Short summary"
```

Preview only:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\initialize-factory-project.ps1 -ProjectName "My Project" -ProjectSummary "Short summary" -CheckOnly
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
