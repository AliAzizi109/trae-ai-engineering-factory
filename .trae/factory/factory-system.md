# Factory System

## Purpose

This document explains the architecture delta between built-in Trae behavior,
repository-integrated Trae behavior, and the factory-only layer that remains in
this baseline.

## Native Trae

- The top-level Agent or SOLO Agent experience is native to Trae.
- Native project rules under `.trae/rules/` are the canonical home for
  repository constraints and safety policy.
- Native project subagents under `.trae/agents/` are the canonical home for
  callable specialist prompts when the active workspace supports them.
- Native project skills under `.trae/skills/` are the canonical home for
  reusable SOPs and checklists.

## Repository Integration Layer

Use only the canonical capability truth labels defined by the repository contract.

- `AGENTS.md` is a thin cross-tool rule file that keeps shared operating rules
  and capability labels readable outside any single prompt surface.
- `.trae/agent-specs.md` remains the documented manual fallback only for
  `Coder` and `CodeReviewer` when native project subagents are unavailable.
- `.trae/mcp.json` is repository-tracked MCP wiring that aligns with Trae's
  project-scoped configuration model.
- `.trae/factory/config/*.json` defines repository metadata for routing,
  handoffs, and baseline custody. These files describe repository intent and
  operator structure; they do not by themselves prove native runtime behavior.

## Factory-Only Layer

- Persistent task state under `.trae/factory/tasks/*.json` is a repository-backed
  durability layer rather than native Trae state.
- Factory scripts under `scripts/` implement bootstrap, baseline sync,
  initialization, task creation, task updates, summaries, and operator
  dashboards.
- The factory-only layer is where recovery context, evidence gating, baseline
  adoption, and cross-session operator visibility are preserved.

## Runtime Boundaries

- Repository-defined `.trae/agents/*` should not be claimed as runtime-callable
  unless the active Trae workspace actually exposes and supports them.
- Repository metadata about routing or handoffs should be treated as repository
  contracts, not proof that the runtime enforces them automatically.
- Windows runtime limitations, workspace feature flags, and account-level agent
  availability still affect what is truly native in practice.

## Recovery And Operator Notes

- Use `README.md` as the human entrypoint and operator quickstart.
- Use `.trae/factory/verification-matrix.md` for repo-specific capability truth.
- Use `.trae/factory/tasks/` plus the factory scripts for durable state,
  summaries, dashboards, and recovery checkpoints.
