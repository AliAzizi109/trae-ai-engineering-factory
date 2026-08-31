# Current Project State

Last updated: 2026-08-31

## Project Identity

- Name: Trae AI Engineering Factory
- Summary: Reusable Trae-based factory baseline for initializing new repositories with less manual setup.

## Current Operating State

- The repository is being maintained as a reusable factory baseline for Trae workspaces.
- Native project subagents exist under `.trae/agents/`, while manual fallback remains documented in `.trae/agent-specs.md`.
- Persistent task-state support remains active under `.trae/factory/tasks/` and is still the durable factory layer for recovery and operator visibility.
- Baseline custody and adopter sync remain manifest-driven through `.trae/factory/config/baseline-files.manifest.json`.

## Current Scope

- Keep the factory behavior tracked in the repository instead of inside one device.
- Keep bootstrap and adopter initialization reproducible across machines.
- Reduce documentation duplication without weakening review, QA, and approval gates.
- Preserve truthful separation between native Trae capability, repository integration, and factory-only durability.

## Active Components

- Cross-tool rules: `AGENTS.md`
- Authoritative rule layer: `.trae/rules/00-constitution.md`
- Project subagents: `.trae/agents/`
- Manual fallback setup: `.trae/agent-specs.md`
- Architecture delta and capability truth: `.trae/factory/`
- Durable task state and operator workflows: `.trae/factory/tasks/` and `scripts/`
- Project MCP wiring: `.trae/mcp.json`

## Open Problems

- `pytest` is not installed in the current environment, so local execution-based verification remains incomplete.
- Native project subagent behavior still depends on the active workspace supporting the required Trae features.
- Windows runtime limitations still prevent treating sandbox isolation as fully native in this environment.
- Portable MCP configuration does not change the runtime fact that live access remains scoped to the active workspace.

## Immediate Next Step

Use this baseline for the next approved task while keeping PASS 2 focused on metadata thinning and script/config alignment rather than widening the documentation layer.
