---
alwaysApply: true
scene: git_message
---

# Git Commit Message Rules

Use this file as the single canonical source for Trae git commit message generation.

- Format subjects as `type(scope): subject`.
- Keep the subject to one line by default.
- Use a direct imperative verb.
- Describe the actual change truthfully, narrowly, and with the changed area named precisely.
- Do not use vague wording such as `update`, `misc`, `cleanup`, `improve`, or `stuff` without a concrete outcome.
- Do not make fake native, runtime, platform, or production claims unless the diff directly proves them.
- Keep one cohesive concern per commit; do not bundle unrelated changes into one message.
