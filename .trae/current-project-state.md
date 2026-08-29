# Current Project State

Last updated: 2026-08-29

## Project Identity

- Name: Trae Factory Test
- Summary: Reusable Trae-based factory baseline for initializing new repositories with less manual setup.

## Completed Tasks

- The project direction for V1.0 was settled on Trae Ultra as the main platform, instead of relying on Prime Agent or bb as the primary execution environment.
- The core factory loop was validated in prior work: implementation, independent review, fix loop, testing, branch, pull request, and human approval.
- The repository is connected to GitHub and is intended to be the source of truth across devices.
- The following factory control files exist in this repository:
  - `AGENTS.md`
  - `.trae/rules/00-constitution.md`
  - `.trae/agent-specs.md`
- The `Coder` and `CodeReviewer` custom agents already exist and were tested manually.
- The local MCP issue on Windows was debugged and resolved for the filesystem server.
- The project-level MCP baseline is now stored in the repository through:
  - `.trae/mcp.json`
  - `scripts/bootstrap-factory.ps1`
  - `scripts/bootstrap-project-fs.ps1`
  - `.gitignore`
  - `.trae-local/mcp/project-fs/package.json`
  - `.trae-local/mcp/project-fs/package-lock.json`
- The multi-device baseline was independently reviewed. The first review failed on determinism and path stability, those issues were fixed, and the re-review passed.
- The baseline commit was finalized and pushed to GitHub for reuse across devices.
- `test_poc/test_calc.py` was extended with additional validation-path tests, including `TypeError` and `NaN` coverage.
- The project now has a single bootstrap entrypoint that validates the baseline and then runs the project-fs setup.
- The baseline now supports initializing a new repository identity through `scripts/initialize-factory-project.ps1`.
- The initializer behavior was generalized so README updates apply only while a repository still uses the baseline identity header; adopted repositories can keep a project-specific README without being reshaped on every run.
- The baseline docs portability rule is now explicit: active operating documents should use repository-relative links, while historical `file:///` links are fixed only when a document becomes an active entrypoint again.

## Current Task And Scope

The project is currently in the stabilization phase for a reusable Trae-based factory baseline.

Current scope:

- Keep the factory behavior inside the repository rather than inside one device.
- Make the setup reproducible across multiple devices with GitHub plus a single bootstrap step.
- Continue reducing manual setup and manual orchestration while preserving review and approval gates.
- Keep the reusable initializer adoption-safe across project-specific repositories instead of assuming every repo keeps the baseline README shape.
- Keep active operating documentation portable across machines by preferring repository-relative links.

Primary files in the current scope:

- `AGENTS.md`
- `.trae/rules/00-constitution.md`
- `.trae/agent-specs.md`
- `.trae/mcp.json`
- `scripts/bootstrap-factory.ps1`
- `scripts/bootstrap-project-fs.ps1`
- `scripts/initialize-factory-project.ps1`
- `.trae-local/mcp/project-fs/package.json`
- `.trae-local/mcp/project-fs/package-lock.json`
- `.gitignore`

## Baseline Files

Files that should travel through GitHub across devices:

- `AGENTS.md`
- `.trae/rules/00-constitution.md`
- `.trae/agent-specs.md`
- `.trae/current-project-state.md`
- `.trae/mcp.json`
- `scripts/bootstrap-factory.ps1`
- `scripts/bootstrap-project-fs.ps1`
- `scripts/initialize-factory-project.ps1`
- `.gitignore`
- `.trae-local/mcp/project-fs/package.json`
- `.trae-local/mcp/project-fs/package-lock.json`

## Baseline Commit Set

The current baseline commit set should include:

- `AGENTS.md`
- `.trae/rules/00-constitution.md`
- `.trae/agent-specs.md`
- `.trae/current-project-state.md`
- `.trae/mcp.json`
- `scripts/bootstrap-factory.ps1`
- `scripts/bootstrap-project-fs.ps1`
- `scripts/initialize-factory-project.ps1`
- `.gitignore`
- `.trae-local/mcp/project-fs/package.json`
- `.trae-local/mcp/project-fs/package-lock.json`

## Excluded From Baseline For Now

The following file remains part of the repository, but is not part of the
current baseline commit set:

- `test_poc/test_calc.py`

Reason: this changes the experimental/validation Python project and is not required for the multi-device factory baseline.

## Local Artifacts

Items that should remain local to a machine or session:

- root chat transcripts such as `chat-*.txt`
- local debug notes such as `debug-mcp-routing-error.md`
- local debug folders such as `.dbg/`
- local dependency installs such as `.trae-local/mcp/project-fs/node_modules/`
- local MCP install logs such as `.trae-local/mcp/project-fs/npm-debug.log*`

## Tech Stack

- Trae Ultra
- Built-in Agent orchestration
- Custom agents:
  - `Coder`
  - `CodeReviewer`
- Project rules via `.trae/rules`
- Project-wide agent guidance via `AGENTS.md`
- Project-level MCP via `.trae/mcp.json`
- MCP filesystem server:
  - `@modelcontextprotocol/server-filesystem`
  - `zod`
- Git
- GitHub private repository
- Windows
- PowerShell
- Node.js / npm
- Python
- `pytest` as the intended test runner for the sample Python test project

## Open Problems And Unresolved Items

- `pytest` is not installed in the current environment, so local execution-based verification is incomplete.
- `Coder` was confirmed to use MCP for reading, but it still preferred built-in editing for writing. This is not a blocking issue, but it remains an observed behavior.
- The current bootstrap is Windows-first because it explicitly uses `npm.cmd`.
- The next adoption still needs to be validated on another repository, not only inside this baseline repository itself.
- Some historical or archive documents may still contain older machine-specific `file:///` links; those should be updated only when the document becomes an active operating reference again.

## Next Recommended Step

Use this baseline in a first real project adoption on another repository and validate the generalized initializer flow plus the docs portability rule there.
