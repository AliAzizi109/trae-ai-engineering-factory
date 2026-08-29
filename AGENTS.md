# AI Engineering Factory

This project is currently operated as an AI Engineering Factory.

## Roles

- SOLO/Main acts as the coordinator.
- The current factory baseline is designed around these custom agents when
  they are configured through `Agent -> Create`:
  - CodeReviewer
  - Coder

## Required Workflow

All work follows this required flow:

1. Research
2. Plan
3. Implement
4. Review
5. Test
6. Human approval

## Safety

- Any deploy requires explicit human approval.
- Any merge requires explicit human approval.
- Any destructive command requires explicit human approval.
- Project rules under `.trae/rules/` remain authoritative for this repo.

## Bootstrap

For a new machine or fresh clone, use the single project entrypoint:

`powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-factory.ps1`
