<div align="center">

# OpenCode Go Worker

**Codex plans. OpenCode executes. Codex reviews.**

一个极简的 Codex Skill，用一次性的 `opencode run` 把代码修改交给 OpenCode Go 执行。

![Codex Skill](https://img.shields.io/badge/Codex-Skill-111827?style=for-the-badge)
![OpenCode](https://img.shields.io/badge/OpenCode-one--shot-2563eb?style=for-the-badge)
![No Daemon](https://img.shields.io/badge/no-daemon-16a34a?style=for-the-badge)
![Safe By Default](https://img.shields.io/badge/no-dangerous-permissions-dc2626?style=for-the-badge)

</div>

---

## What It Does

`opencode-go-worker` gives Codex a tiny delegation lane:

```text
Codex analyzes the task
-> writes .ai/OC_TASK.md
-> calls the wrapper
-> wrapper runs one opencode run
-> OpenCode edits files
-> OpenCode exits
-> Codex reviews git status / git diff
```

It is intentionally small. No Codex subagents. No OpenCode TUI. No `opencode serve`. No background process.

## Table Of Contents

- [Why](#why)
- [Files](#files)
- [Install](#install)
- [Usage](#usage)
- [Default Models](#default-models)
- [Safety Rules](#safety-rules)
- [Wrapper Commands](#wrapper-commands)
- [Verification](#verification)

## Why

Use this when you want Codex to stay as the reviewer and decision-maker, while OpenCode does the mechanical code edits through a cheaper or separate execution model.

Good fit:

- small code changes
- config/docs edits
- focused bug fixes
- low-cost model execution experiments
- "Codex decides, OpenCode Go works" workflows

Bad fit:

- analysis-only requests
- no-command requests
- tasks where you do not want code edited
- broad refactors with unclear ownership

## Files

```text
.
├─ SKILL.md
├─ run_oc_worker.ps1
├─ run_oc_worker.sh
└─ research.md
```

## Install

Clone or download this repository, then place the folder where Codex can discover global skills:

```powershell
$target = "$HOME\.agents\skills\opencode-go-worker"
New-Item -ItemType Directory -Force -Path $target
Copy-Item .\SKILL.md, .\run_oc_worker.ps1, .\run_oc_worker.sh, .\research.md -Destination $target -Force
```

Optional global route in `$HOME\.codex\AGENTS.md`:

```markdown
## OpenCode Go one-shot worker

When the user asks for "OpenCode Go 干活", "Codex 决策 OpenCode 执行", "开启 OpenCode 执行", "低成本模型改代码", or explicitly mentions `$opencode-go-worker`, use the `opencode-go-worker` skill.

Use one-shot `opencode run` only.

Do not use it for analysis-only, no-code-change, no-command, or no-OpenCode requests.
```

## Usage

Natural-language trigger:

```text
开启 OpenCode 执行，让 Codex 决策，OpenCode Go 干活。目标：修复 xxx。
```

Explicit trigger:

```text
请使用 $opencode-go-worker。目标：修复 xxx。
```

Analysis-only guardrail:

```text
只分析，不要调用 OpenCode，不要改代码。目标：检查 xxx。
```

## Default Models

The skill defines these intended defaults:

| Task type | Model |
| --- | --- |
| small/docs/config | `opencode-go/deepseek-v4-flash` |
| normal coding | `opencode-go/kimi-k2.7-code` |
| harder fix | `opencode-go/deepseek-v4-pro` |

Important: the local research snapshot did not confirm that `opencode-go/*` model IDs were visible on the tested machine. Run this first:

```powershell
opencode models --refresh
opencode models
```

If those model IDs are not listed, pass an available `provider/model` to the wrapper or update your OpenCode provider configuration.

## Safety Rules

- One task, one `opencode run`.
- No Codex custom subagent.
- No OpenCode custom agent.
- No OpenCode TUI.
- No `opencode serve`.
- No long-running background process.
- No recursive delegation.
- No `--dangerously-skip-permissions`.
- Always review `git status --short` and `git diff --stat` after execution.

## Wrapper Commands

PowerShell:

```powershell
.\run_oc_worker.ps1 `
  -TaskFile ".ai\OC_TASK.md" `
  -Model "opencode-go/kimi-k2.7-code" `
  -Agent "build" `
  -ProjectDir "." `
  -TimeoutSec 1800
```

Bash:

```bash
./run_oc_worker.sh \
  --task-file ".ai/OC_TASK.md" \
  --model "opencode-go/kimi-k2.7-code" \
  --agent "build" \
  --project-dir "." \
  --timeout-sec 1800
```

## Verification

Lightweight checks:

```powershell
Test-Path "$HOME\.agents\skills\opencode-go-worker\SKILL.md"
Test-Path "$HOME\.agents\skills\opencode-go-worker\run_oc_worker.ps1"
Test-Path "$HOME\.agents\skills\opencode-go-worker\run_oc_worker.sh"
Test-Path "$HOME\.agents\skills\opencode-go-worker\research.md"
opencode models --refresh
opencode models
```

Do not run the wrapper unless you actually want OpenCode to spend model usage and edit files.
