# Task Tracking

## Model

- Store one markdown file per task in this directory.
- Create tasks from `.trae/factory/templates/task.md`.
- Keep task files concise, factual, and append-only where practical.
- Treat the task file as the recovery source for plan, execution log, evidence, and retry notes.

## Required Fields

- Task ID
- Objective
- Phase
- Responsible agent
- Status
- Plan
- Findings
- Execution Log
- Evidence
- Retry History
- Capability Classification
- Review result
- Security result
- Test result
- Remaining work
- Final approval

## Usage

- Use `scripts/new-factory-task.ps1` to create a new task file with a generated Task ID.
- Use `scripts/update-factory-task.ps1` to safely update status fields and append bullets to Findings, Remaining Work, Execution Log, or Evidence.
- Update the same task file through the workflow instead of scattering status across multiple docs.
- Mark unfinished checks explicitly instead of implying completion.
