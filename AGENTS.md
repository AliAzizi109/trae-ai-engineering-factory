# AI Engineering Factory

This project operates as an AI Engineering Factory.

This repository keeps a small set of project rules that should stay readable across tools and runtimes.

## Core Operating Rules

- Follow this workflow: intake, discovery, research, plan, implement, review, security review, QA / test, release gate, human approval.
- Require explicit human approval before any deploy, merge, destructive command, or production change.
- Prefer configured reviewer and verifier paths only when the active runtime actually supports them.
- Treat project rules under `.trae/rules/` as authoritative when summary documents differ.

## Truth Labels

Use these labels exactly when discussing capability:

- `Native Trae`: behavior provided directly by the active Trae runtime.
- `Verified Runtime`: behavior directly confirmed in the active environment.
- `Repository Implementation`: behavior documented or implemented in this repository only.
- `Workaround`: useful fallback that is not native durable runtime behavior.
- `Limitation`: boundary that cannot be safely closed in this runtime without human help or platform support.

## Runtime Warning

- Do not assume a repo-defined contract, role, or spec file is runtime-callable just because it exists in version control.
- Treat native Trae capability as true only when the active workspace/runtime exposes and supports it.
- Use repository fallbacks truthfully, and label them as repository implementations or workarounds instead of native features.

## Pointers

- Use `README.md` as the human entrypoint and operator quickstart.
- Use `.trae/agent-specs.md` only for manual fallback setup of Coder and CodeReviewer.
- Use `.trae/factory/factory-system.md` for the architecture delta between Trae and the factory layer.
- Use `.trae/factory/verification-matrix.md` for repo-specific capability truth and matrix notes.
