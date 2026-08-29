# Trae Factory Test

## What This Repository Is

This repository is a small, reusable baseline for running an AI engineering factory inside a Trae workspace. It keeps the operating rules, agent setup guidance, project-level MCP wiring, and bootstrap scripts in version control, plus a minimal Python proof-of-concept test under `test_poc/`.

## Why It Exists / Benefits

- Moves critical factory behavior into the repository instead of keeping it on one machine.
- Makes new-machine setup reproducible with one bootstrap entrypoint.
- Preserves a disciplined workflow: research, plan, implementation, review, testing, and human approval.
- Separates tracked baseline files from machine-local artifacts.

## Repository Structure

```text
.
├─ AGENTS.md
├─ .trae/
│  ├─ agent-specs.md
│  ├─ current-project-state.md
│  ├─ mcp.json
│  └─ rules/
│     └─ 00-constitution.md
├─ .trae-local/
│  └─ mcp/
│     └─ project-fs/
│        ├─ package.json
│        └─ package-lock.json
├─ scripts/
│  ├─ bootstrap-factory.ps1
│  └─ bootstrap-project-fs.ps1
└─ test_poc/
   └─ test_calc.py
```

## Factory Baseline Files

The following tracked files define the reusable factory baseline:

- `AGENTS.md`: repository-level operating model, workflow, roles, and safety expectations.
- `.trae/rules/00-constitution.md`: the authoritative factory constitution and required pipeline.
- `.trae/agent-specs.md`: manual setup specifications for custom agents such as `Coder` and `CodeReviewer`.
- `.trae/current-project-state.md`: current baseline status, scope, local-artifact policy, and open items.
- `.trae/mcp.json`: project-scoped MCP configuration that points the filesystem server at the current workspace.
- `scripts/bootstrap-factory.ps1`: the main entrypoint; validates the baseline and then bootstraps local MCP dependencies.
- `scripts/bootstrap-project-fs.ps1`: installs the local project-fs MCP dependencies deterministically with `npm ci`.
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
4. Create or verify the `Coder` and `CodeReviewer` custom agents from `.trae/agent-specs.md` if they are not already available in your Trae account.
5. Run the single bootstrap entrypoint:

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
git status
```
Shows tracked, modified, and untracked files before sync, staging, or review.

```powershell
python -m pytest .\test_poc\test_calc.py
```
Runs the small Python proof-of-concept test, if Python and `pytest` are available.

## Daily Workflow

1. Pull or sync the current branch from GitHub when it is safe to do so.
2. Run the bootstrap command on a new machine, or rerun it if local MCP dependencies are missing.
3. Make sure the required custom agents are present and aligned with `.trae/agent-specs.md`.
4. Work through the required flow: Research -> Plan -> Implement -> Review -> Test -> Human approval.
5. Run the relevant checks for the files you changed.
6. Review `git status` and stage only the intended files.
7. Commit, push, merge, or deploy only when the human explicitly approves.

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
- Custom agent definitions should be recreated or verified from `.trae/agent-specs.md` when account-level agent state is missing or out of date.
- Commit tracked baseline changes; do not sync local dependency installs or session/debug artifacts.
- The current bootstrap flow is Windows-first because the local install script resolves `npm.cmd` from PowerShell.
