# QA Verification SOP

## Purpose

Use this skill when you need a reusable verification procedure for implementation work. This skill is intentionally repo-agnostic and focuses on how to verify changes, record evidence, and report limits truthfully.

## When To Use

- After implementation and review are complete
- When producing a QA or verification verdict
- When a task needs a repeatable checklist for targeted checks

## Procedure

1. Confirm scope
   - Restate the requested change and the files that were allowed to change.
   - Note any explicit constraints or prohibited paths before running checks.

2. Pick targeted checks
   - Prefer the smallest set of commands or manual checks that can validate the requested change.
   - Choose checks that match the change type: docs, config, code path, tests, or runtime behavior.

3. Run verification
   - Execute the selected checks.
   - Capture concrete evidence: commands, outputs, artifacts, screenshots, or reasoning when no command applies.

4. Evaluate result
   - PASS when the requested change is verified and no blocking issue remains.
   - FAIL only for blocking correctness, safety, security, or regression issues.
   - If a check cannot run, disclose that clearly and mark the coverage gap.

5. Report truthfully
   - List what was checked.
   - List what was not checked.
   - State the verifier path used and any runtime/tooling limitations.

## Checklist

- Scope matches the user request
- Changed files stay inside the allowed boundary
- Review findings are resolved or explicitly carried forward
- Relevant tests/checks were run or explicitly marked not possible
- Evidence is concrete and reproducible
- PASS/FAIL reasoning is tied to observed results

## Output Template

- Scope:
- Checks run:
- Evidence:
- Skipped or not possible:
- Risks or follow-ups:
- Verdict:

## Guardrails

- Do not claim coverage you did not actually perform.
- Do not convert missing evidence into a PASS.
- Do not rely on repo-specific capability tables inside this skill; keep it reusable.
