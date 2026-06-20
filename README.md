<div align="center">

# OpenCode Go Worker

**A Codex Skill that treats OpenCode as a short-lived execution worker.**

Codex plans and reviews. OpenCode executes bounded tasks. The wrapper resolves models dynamically from `opencode models`.

![Codex Skill](https://img.shields.io/badge/Codex-Skill-111827?style=for-the-badge)
![Short Lived Worker](https://img.shields.io/badge/OpenCode-short--lived--worker-2563eb?style=for-the-badge)
![No Daemon](https://img.shields.io/badge/no-daemon-16a34a?style=for-the-badge)
![Paid Opt In](https://img.shields.io/badge/paid-fallback-explicit-dc2626?style=for-the-badge)

</div>

---

## Positioning

`opencode-go-worker` is a small Codex Skill for delegating bounded code edits to OpenCode without turning OpenCode into a long-running agent system.

It is:

- a short-lived worker pattern
- one `opencode run` per wrapper call
- Codex-controlled planning and review
- dynamic model selection from visible `opencode models`
- OpenCode Go first, free fallback second, paid fallback only by explicit opt-in

It is not:

- a full multi-agent framework
- a daemon
- OpenCode TUI
- `opencode serve`
- an auto-commit or auto-push tool
- a hidden paid-provider router

## Flow

```text
Codex plans
-> Codex writes .ai/OC_TASK.md
-> wrapper resolves model and agent
-> wrapper runs one short-lived opencode run
-> OpenCode exits
-> Codex reviews git status / git diff
-> Codex decides whether to stop or prepare another round
```

Default rounds: `1`.
Hard limit: `3`.
The wrapper never loops by itself.

## Files

```text
.
├─ SKILL.md
├─ run_oc_worker.ps1
├─ run_oc_worker.sh
├─ research.md
└─ README.md
```

## Install

Clone or download this repository, then place the skill files where Codex can discover global skills:

```powershell
$target = "$HOME\.agents\skills\opencode-go-worker"
New-Item -ItemType Directory -Force -Path $target
Copy-Item .\SKILL.md, .\run_oc_worker.ps1, .\run_oc_worker.sh, .\research.md -Destination $target -Force
```

Optional global route in `$HOME\.codex\AGENTS.md`:

```markdown
## OpenCode Go short-lived worker

When the user asks for "OpenCode Go 干活", "Codex 决策 OpenCode 执行", "开启 OpenCode 执行", "低成本模型改代码", or explicitly mentions `$opencode-go-worker`, use the `opencode-go-worker` skill.

Use short-lived `opencode run` only. Codex plans and reviews; OpenCode executes bounded tasks.

Do not use it for analysis-only, writing-only, no-code-change, no-command, or no-OpenCode requests.
```

## Modes

### USER_TASK

Default mode for user projects.

Allowed:

- code edits
- bug fixes
- config fixes
- test fixes
- project documentation updates

Forbidden:

- modifying this plugin
- syncing global Skill files
- auto `git add`, `git commit`, or `git push`
- pure web research
- long-form analysis writing
- analysis-only tasks

If the target directory looks like this plugin repository, USER_TASK mode refuses to run.

### MAINTAIN_SKILL

Only use when the user explicitly asks to maintain `opencode-go-worker` itself.

Even in this mode, do not commit or push unless the user explicitly asks.

## Model Resolution

The wrapper reads real available models from:

```powershell
opencode models --refresh
opencode models
```

Resolution strategy:

1. If `-Model` / `--model` is provided, use it only if it exists.
2. If no model is provided, prefer `opencode-go/*`.
3. If no Go model is visible, allow free/zero-extra-cost fallback providers by default:
   - `opencode/*`
   - `copilot/*`
   - `github-copilot/*`
   - `gemini/*`
   - `google/*`
4. Paid fallback is disabled by default. It requires explicit opt-in:
   - PowerShell: `-AllowPaidFallback`
   - Bash: `--allow-paid-fallback`

Paid providers are never selected silently.

Model intent hints:

| Intent | Preference |
| --- | --- |
| `small`, `docs` | `flash`, `mini`, `lite`, `fast`, `small` |
| `coding` | `code`, `coder`, `k2`, `deepseek`, `qwen`, `glm` |
| `hard` | coding-like names, avoiding `flash`, `mini`, `lite` when possible |
| `review` | faster models |

Every dry run and real run prints:

- selected model
- selected provider
- selection reason
- whether fallback was used
- selected agent
- command preview

## Task File Template

`.ai/OC_TASK.md` should stay short:

```md
# OC Task

## Mode
USER_TASK

## Objective
一句话说明任务。

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
命令；没有测试就写：No test command. Explain why.

## Report
Return:
- changed files
- test result
- blockers
- summary
```

## PowerShell Usage

Help:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_oc_worker.ps1 -Help
```

Dry run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_oc_worker.ps1 -DryRun -ProjectDir C:\path\to\repo
```

One real worker round:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_oc_worker.ps1 `
  -TaskFile ".ai\OC_TASK.md" `
  -ProjectDir C:\path\to\repo `
  -ModelIntent coding
```

Maintain this skill repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_oc_worker.ps1 `
  -Mode MAINTAIN_SKILL `
  -DryRun
```

## Bash Usage

Help:

```bash
./run_oc_worker.sh --help
```

Dry run:

```bash
./run_oc_worker.sh --dry-run --project-dir /path/to/repo
```

One real worker round:

```bash
./run_oc_worker.sh \
  --task-file ".ai/OC_TASK.md" \
  --project-dir /path/to/repo \
  --model-intent coding
```

## Verification

Lightweight checks that do not run `opencode run`:

```powershell
opencode models --refresh
opencode models
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_oc_worker.ps1 -Help
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_oc_worker.ps1 -DryRun -Mode MAINTAIN_SKILL
```

Use `-Mode MAINTAIN_SKILL` for dry-running inside this repository because USER_TASK intentionally refuses to run in the plugin repo.
