# AI Engineering Factory

This project is currently operated as an AI Engineering Factory.

## Roles

- SOLO/Main acts as the coordinator.
- The operational V2 role source of truth lives under:
  - `.trae/factory/config/role-system.json`
  - `.trae/factory/config/model-routing.json`
  - `.trae/factory/config/handoffs.json`
- Prefer these native project subagents when Trae exposes them in the
  repository, with these contract mappings:
  - `factory-reviewer` -> `code_reviewer`
  - `security-reviewer` -> `security_reviewer`
  - `qa-verifier` -> `qa_test_verifier`
- Primary V4-A runtime path in this environment is:
  - `security_reviewer` -> built-in `code-reviewer`
  - `qa_test_verifier` -> built-in `default` in verification-only mode
- `qa_test_verifier` PASS or FAIL should now be recorded with structured
  `qa_verification` evidence in task state. A terminal QA verdict without
  explicit checks, commands/artifacts, skipped/not-possible disclosure, and
  verifier path metadata is treated as insufficient evidence.
- The baseline also supports these manual fallback agents when they are
  configured through `Agent -> Create`:
  - CodeReviewer
  - Coder
- If the primary runtime path is unavailable, the truthful fallback coverage
  is:
  - Implementation: `Coder`
  - Independent code review: `CodeReviewer`
  - Security review: manual `CodeReviewer` security-scoped pass configured
    through `Agent -> Create`, or chief orchestrator disclosure when that
    fallback is unavailable
  - QA verification: chief orchestrator runs targeted checks and records
    evidence in task state

Files under `.trae/agents/*.md` remain `Repository Implementation`. They can
document repository behavior and prompts, but they are not proof by themselves
that Trae can invoke those repo-defined agents at runtime.

## Required Workflow

All work follows this required flow:

1. Intake
2. Discovery
3. Research
4. Plan
5. Implement
6. Review
7. Security Review
8. QA / Test
9. Release Gate
10. Human approval

## Safety

- Any deploy requires explicit human approval.
- Any merge requires explicit human approval.
- Any destructive command requires explicit human approval.
- Project rules under `.trae/rules/` remain authoritative for this repo.

## Truth Labels

Use these labels exactly when discussing capability:

- `Native Trae`: feature provided by Trae itself.
- `Verified Runtime`: behavior directly confirmed in this environment.
- `Repository Implementation`: behavior implemented by tracked files here.
- `Workaround`: useful emulation, not native durable runtime behavior.
- `Limitation`: known runtime boundary with no safe native implementation here.

Do not claim repository-defined `.trae/agents/*` are runtime-callable unless
that behavior is verified in the active Trae workspace.

## Bootstrap

For a new machine or fresh clone, use the single project entrypoint:

`powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-factory.ps1`

For persistent task state, create task records with:

`powershell -ExecutionPolicy Bypass -File .\\scripts\\new-factory-task.ps1 -Objective "Task objective"`

Inspect model selection with:

`powershell -ExecutionPolicy Bypass -File .\\scripts\\select-factory-model.ps1 -Role chief_orchestrator`

Inspect a task summary with:

`powershell -ExecutionPolicy Bypass -File .\\scripts\\get-factory-task-summary.ps1 -TaskPath ".trae\\factory\\tasks\\task-id.json"`

`TaskPath` may be provided as a task filename, a repo-relative task path, or an absolute path.
