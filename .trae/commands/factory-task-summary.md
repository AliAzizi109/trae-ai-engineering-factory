Name: factory-task-summary
Description: Summarize authoritative factory task state from repository task records.

---

1. Use `.trae/factory/tasks` as the authoritative repository persistence for task state.
2. If the user names a task file, read only that file from `.trae/factory/tasks`. If the requested path falls outside that directory, refuse it. If no task file is specified, choose the newest task file in `.trae/factory/tasks` by last modified time and state the exact file used.
3. Extract and report:
   - `Task ID`
   - `Objective`
   - `Current Phase / Role / Model`
   - `Status`
   - `Key Findings`
   - `Blockers`
   - `Verification Status`
   - `Next Automatic Action`
   - `Recommended Immediate Next Step`
4. Prefer direct values from the task JSON. If fields are missing, state `not recorded` instead of guessing.
5. Treat `Next Automatic Action` as advisory and operator-facing only. It never self-authorizes execution; execution authority remains with the active Agent or SOLO runtime and any required human approvals.
6. Do not execute any action from task state alone. If `Next Automatic Action` would require a database change, deploy, merge, destructive action, or production action, flag that it still requires explicit human approval.
7. If current conversation state conflicts with the task JSON, call out the difference explicitly and do not silently reconcile it.
8. This command is read-only. Do not modify task JSON, factory scripts, or any repository state.
9. Keep the summary concise, operational, and grounded in the selected task record.
