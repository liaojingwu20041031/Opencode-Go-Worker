---
name: opencode-go-worker
description: "Use when the user wants Codex to plan/review and OpenCode Go to execute code edits via one-shot opencode run. Trigger words: OpenCode Go, opencode worker, OpenCode干活, Codex决策OpenCode执行, 开启OpenCode执行, 低成本模型改代码. Do not use for analysis-only or no-code-change requests."
---

# OpenCode Go Worker

Use this skill for one-shot delegation:

Codex plans and reviews. OpenCode Go executes.

## Trigger

Use when the user asks:
- OpenCode Go 干活
- 开启 OpenCode 执行
- Codex 决策，OpenCode 执行
- 用低成本模型改代码
- 调 opencode run 修改代码

Do not use when the user asks:
- 只分析
- 不要改代码
- 不要执行命令
- 不要调用 OpenCode
- 只给方案

## Workflow

1. Codex creates `.ai/OC_TASK.md`.
2. Codex calls `run_oc_worker`.
3. `run_oc_worker` runs one `opencode run`.
4. OpenCode finishes and exits.
5. Codex checks `git status --short` and `git diff --stat`.
6. Codex reports result.

## Rules

- No Codex subagent.
- No OpenCode TUI.
- No opencode serve.
- No background daemon.
- No recursive delegation.
- No `--dangerously-skip-permissions`.
- One task, one `opencode run`.
- Keep task small.
- Always review diff after execution.

## Default models

- small/docs/config: `opencode-go/deepseek-v4-flash`
- normal coding: `opencode-go/kimi-k2.7-code`
- harder fix: `opencode-go/deepseek-v4-pro`

If `opencode models` does not show the requested `opencode-go/*` model, stop and ask the user to choose an available model or update OpenCode/provider configuration.

## Task file format

`.ai/OC_TASK.md` must include:

- Objective
- Allowed files
- Forbidden changes
- Steps
- Test command
- Final report requirement

