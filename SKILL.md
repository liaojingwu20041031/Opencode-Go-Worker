---
name: opencode-go-worker
description: "Codex-controlled OpenCode worker. Use when Codex should plan/review and OpenCode should execute bounded code edits through short-lived opencode run. Dynamically resolve models from opencode models; prefer OpenCode Go, allow free fallback, never silently use paid providers. Do not use for analysis-only, writing-only, no-code-change, no-command, or no-OpenCode requests."
---

# OpenCode Go Worker

Codex controls.
OpenCode executes.
Wrapper resolves model dynamically.
Each run is short-lived.

## Modes

Use `USER_TASK` by default for bounded edits in a user project:
- code changes
- bug fixes
- config fixes
- test fixes
- project documentation updates

Do not use `USER_TASK` for:
- modifying this skill/plugin
- syncing global skills
- auto `git add`, `git commit`, or `git push`
- pure web research
- long-form analysis writing
- analysis-only or no-code-change requests

Use `MAINTAIN_SKILL` only when the user explicitly asks to fix or maintain `opencode-go-worker` itself.
Even in `MAINTAIN_SKILL`, do not commit or push unless explicitly requested.

## Rounds

- Default `MaxRounds = 1`.
- Hard limit `MaxRounds = 3`.
- Each round is exactly one `opencode run`.
- The wrapper executes one round only.
- Codex must review `git status --short` and `git diff --stat` after each round before deciding another round.
- Regenerate or update `.ai/OC_TASK.md` before each new round.

## Rules

- No daemon.
- No TUI.
- No serve.
- No recursive delegation.
- No auto commit/push.
- No `--dangerously-skip-permissions`.
- No hidden paid fallback.
- Keep tasks small and file-scoped.

## Model Policy

Let the wrapper resolve models from `opencode models`.

Priority:
1. Explicit `Model`: use only if present; otherwise stop.
2. Prefer `opencode-go/*`.
3. If no Go model is visible and `AllowFreeFallback` is true, allow visible free/zero-extra-cost providers: `opencode/*`, `copilot/*`, `github-copilot/*`, `gemini/*`, `google/*`.
4. Use paid providers only when `AllowPaidFallback` is explicit.

Match `ModelIntent`:
- `small`, `docs`: prefer `flash`, `mini`, `lite`, `fast`, `small`.
- `coding`: prefer `code`, `coder`, `k2`, `deepseek`, `qwen`, `glm`.
- `hard`: prefer coding models that are not `flash`, `mini`, or `lite`.
- `review`: prefer fast models.

## Agent Policy

Use `-Agent auto` unless the task needs a specific OpenCode agent.

Auto mapping:
- edits, bug fixes, implementation, project docs -> `build`
- read-only exploration -> `plan` or `explore`
- risk review or issue finding -> `plan` or `scout`

If an agent is unavailable, fall back to `build` or OpenCode default and report it.

## Task File

Create `.ai/OC_TASK.md`:

```md
# OC Task

## Mode
USER_TASK

## Objective
One sentence.

## Allowed files
- path/to/file

## Forbidden
- Do not edit files outside Allowed files.
- Do not refactor unrelated code.
- Do not commit or push.
- Do not modify opencode-go-worker unless Mode is MAINTAIN_SKILL.

## Steps
1. ...
2. ...

## Test
No test command. Explain why.

## Report
Return:
- changed files
- test result
- blockers
- summary
```

## After Each Round

Codex must inspect:

```sh
git status --short
git diff --stat
```

Then decide whether to stop or prepare the next short-lived round.
