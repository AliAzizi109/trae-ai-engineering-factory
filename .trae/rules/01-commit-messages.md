# Commit Message Rules

Use commit subjects that are strict, truthful, and narrow.

## Required Format

- Use `<type>(<scope>): <subject>`.
- Keep `type` and `scope` lowercase.
- Keep the subject to one line by default.
- Prefer repository patterns such as `refactor(factory): ...`, `fix(skill): ...`, `docs(factory): ...`, and `chore(factory): ...`.

## Subject Rules

- Describe what actually changed in the diff, not intended work, requests, or plans.
- Name the primary changed area truthfully and narrowly; do not imply broader impact than the commit contains.
- Use an imperative verb and keep it precise, such as `normalize`, `align`, `clarify`, `remove`, `tighten`, or `refactor`.
- Keep one cohesive concern per commit; split unrelated concerns into separate commits.

## Prohibited Wording

- Do not use vague subjects such as `update`, `misc`, `cleanup`, `improve`, or `stuff` without a concrete changed outcome.
- Do not make fake runtime, native, platform, or production claims unless the diff directly proves them.
- Do not use a scope or subject that hides repository-only work behind runtime-sounding language.

## Scope Guidance

- Use `factory`, `skill`, `repo`, `rules`, or another directly changed area.
- If the change is only documentation, rules, or metadata, prefer `docs(...)` or `chore(...)` over behavior-heavy wording.

## Examples

- `fix(skill): normalize qa verification skill for runtime registration`
- `refactor(factory): rationalize native Trae ownership and preserve factory-only runtime`
- `docs(factory): clarify capability truth labels`
- `chore(rules): add project commit message rules`
