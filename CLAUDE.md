# CLAUDE.md — Sagap

## Project
Sagap is an Android app that maps home Wi-Fi dead zones from a single walk-through (ARCore position tracking + live signal readings) and recommends where to put the router or an extender.
- Users: Me (solo student developer); end users are students, renters and families with one ISP modem and no floor plan
- Stack: Flutter + Dart, Kotlin platform channels, ARCore, local storage (SQLite or Hive); avoid accounts, cloud backend, Firebase, iOS
- Data access: All scan data stays on the device; nothing is uploaded or shared unless the user exports a report

## How to work
- Read the relevant code before changing it.
- For non-trivial work, state a short plan and the files you will touch before editing.
- Keep each change small and focused on one concern.
- Change only what the task needs. Do not rewrite working code.
- When requirements are ambiguous, ask one clear question and include your recommended answer.
- SPEC.md is the source of truth. Update it when a decision changes.
- After two failed attempts at the same approach, stop and explain before trying a third.
- End each task with: what changed, how it was verified, what is left.

## Code quality
- Match the existing patterns, naming and folder structure.
- Prefer readable, explicit code over clever code.
- Do not add an abstraction until the same logic appears three times.
- Replace magic numbers with named constants.
- Write complete code. No TODO or "rest of code here" placeholders.
- Never swallow errors. Handle them or propagate them with context.
- Never assume a function, API or package exists. Check first.

## Debugging
- Fix the root cause, not the symptom.
- Read the full error and stack trace before acting.
- Do not apply a fix you cannot explain.

## Testing
- Never skip, weaken or delete a test to make it pass.
- Test edge cases and error paths, not only the happy path.
- Use explicit expected values. Never compute expectations with the code under test.
- Wi-Fi scanning and ARCore only work on a real Android device; never claim these features work based on the emulator.

## Git
- Never push or force-push without explicit approval.
- Do not commit unless asked.
- Never run git reset --hard or delete branches without approval.

## Security and data
- Never put secrets in code, logs or commits.
- Never log personal data such as Wi-Fi names (SSID/BSSID), precise location, names or tokens.
- Ask before deleting files or running destructive commands.

## Dependencies and tools
- Ask before adding a dependency. Confirm the package name is real and maintained.
- Do not call network services or live data unless the task requires it.

## Output and tokens
- Be concise. No preamble, no repeating unchanged code.
- Never claim something works without evidence: command output, test result or screenshot.

## Stack-specific
- Flutter: keep widgets small; run `flutter analyze` and `flutter test` before saying done.
- Flutter: keep business logic out of widgets; follow the state-management approach chosen in SPEC.md.
