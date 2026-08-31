# Task Tracking

## Model

- Store one JSON file per active V2 task in this directory.
- Create tasks from `.trae/factory/templates/task-state.template.json`.
- Keep task files concise, factual, and recovery-oriented.
- Treat the JSON task file as the authoritative recovery source for role, phase, model, fallback, findings, evidence, retries, and next automatic action.
- Keep historical markdown task files only as legacy records when they already exist.

## Required Fields

- Task ID
- Objective
- Scope
- Constraints
- Priority
- Current phase
- Current role
- Current model
- Fallback used
- Status
- Findings
- Execution Log
- Events
- Model attempts
- Capability classification
- Review result
- Security result
- QA result
- Retry count
- Blocker
- Next automatic action
- Escalation reason
- Verification summary
- Final outcome

## Usage

- Use `.trae/factory/config/baseline-files.manifest.json` as the authoritative baseline file list for bootstrap validation and safe adopter sync planning.
- Use `scripts/start-factory-task.ps1` when you want one low-friction command that creates a task and immediately prints the task summary and operator status.
- Use `scripts/new-factory-task.ps1` to create a new task file with a generated Task ID.
- Use `scripts/update-factory-task.ps1` to safely update status fields and append findings, events, execution log items, model attempts, verification notes, and artifacts while preserving task-path, handle, and backup hardening.
- Use `scripts/get-factory-task-summary.ps1` when you need a quick human-readable operational summary with normalized operator fields.
- Use `scripts/get-factory-operator-status.ps1` when you need a repo-level or task-level dashboard with active/latest task selection.
- Use `scripts/select-factory-model.ps1` before role execution when you need deterministic preferred/fallback selection.
- Use `scripts/sync-factory-baseline.ps1` in check-only mode first when comparing this baseline against an adopter repository; it skips project-specific files by default and never deletes files.
- Update the same task file through the workflow instead of scattering status across multiple docs.
- Mark unfinished checks explicitly instead of implying completion.

## Truthfulness

- The JSON task record is the authoritative repository implementation for V2 state.
- The markdown template remains legacy and readable, but it is not the authoritative V2 backend.
- Repository-defined `.trae/agents/*` are not treated here as verified runtime-callable agents unless that behavior is directly proven in the active Trae environment.
