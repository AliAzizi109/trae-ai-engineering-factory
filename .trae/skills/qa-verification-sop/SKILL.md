---
name: qa-verification-sop
description: Use this skill after implementation and review to run targeted QA verification, capture concrete evidence, and report a truthful PASS or FAIL.
---

# QA Verification SOP

## Description

Use this skill for a reusable, repo-agnostic QA verification procedure. It is intended to validate completed work, record evidence, and communicate verification limits truthfully.

## When To Use

- After implementation and review are complete
- When producing a QA or verification verdict
- When a task needs a repeatable procedure for targeted checks

## Instructions

1. Confirm scope.
   - Restate the requested change and the files that were allowed to change.
   - Note any explicit constraints or prohibited paths before running checks.

2. Pick targeted checks.
   - Prefer the smallest set of commands or manual checks that can validate the requested change.
   - Match checks to the change type: docs, config, code path, tests, or runtime behavior.

3. Run verification.
   - Execute the selected checks.
   - Capture concrete evidence: commands, outputs, artifacts, screenshots, or explicit reasoning when no command applies.

4. Evaluate the result.
   - PASS when the requested change is verified and no blocking issue remains.
   - FAIL only for blocking correctness, safety, security, or regression issues.
   - If a check cannot run, disclose that clearly and mark the coverage gap.

5. Report truthfully.
   - List what was checked.
   - List what was not checked.
   - State the verifier path used and any runtime or tooling limitations.

## Output

- Scope:
- Checks run:
- Evidence:
- Skipped or not possible:
- Risks or follow-ups:
- Verdict:

## Notes

- Do not claim coverage you did not actually perform.
- Do not convert missing evidence into a PASS.
- Keep this skill reusable and avoid repo-specific capability truth inside it.
