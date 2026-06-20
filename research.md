# opencode-go-worker research

Date: 2026-06-20

## Sources checked

- Official Codex manual: `https://developers.openai.com/codex/codex-manual.md`
- Local Codex skill-creator guidance: `C:\Users\liaoj\.codex\skills\.system\skill-creator\SKILL.md`
- Local commands:
  - `codex --help`
  - `opencode --help`
  - `opencode run --help`
  - `opencode models --help`
  - `opencode models --refresh`
  - `opencode models`

## Conclusions

1. Codex global guidance path: the official manual documents global personal `AGENTS.md` at `~/.codex/AGENTS.md`. This environment also exposes global skills from `C:\Users\liaoj\.codex\skills` and `C:\Users\liaoj\.agents\skills`. Per user request, this skill is installed at `$HOME\.agents\skills\opencode-go-worker`.
2. Codex Skill format: a skill requires `SKILL.md` with YAML frontmatter containing `name` and `description`, followed by Markdown instructions.
3. Skill scripts are supported as bundled resources by the Codex skill-creator guidance. This skill keeps scripts directly in the skill folder because the user requested exactly four files.
4. `opencode run [message..]` is the one-shot command. It runs with a message and exits when the command completes.
5. Local `opencode run --help` confirms these options: `--model`, `--agent`, `--file`, and `--dir`.
6. Local `opencode models --help` confirms `opencode models [provider]` and `--refresh`, described as refreshing the models cache from `models.dev`.
7. `opencode models --refresh` and `opencode models` ran successfully. Current local model list did not show `opencode-go/...`; it showed models including:
   - `opencode/deepseek-v4-flash-free`
   - `deepseek/deepseek-v4-flash`
   - `deepseek/deepseek-v4-pro`
   - `openai/gpt-5.4`
   - `openai/gpt-5.5`
8. Therefore, this machine did not confirm that OpenCode Go model names currently use the `opencode-go/...` prefix. The wrappers keep the requested defaults, but stop if the requested model and requested fallback are not present.
9. `--dangerously-skip-permissions` means auto-approve permissions that are not explicitly denied. The help text marks it dangerous, so wrappers never pass it by default.
10. Timeout protection:
    - PowerShell uses `System.Diagnostics.Process.WaitForExit(timeout)` and kills only the launched opencode process tree on timeout.
    - Bash uses `timeout "$TIMEOUT_SEC" opencode run ...` and requires GNU coreutils `timeout`.

## Local command notes

- `codex --help` failed on this Windows app path with "Access denied"; the Codex manual and local skill-creator guidance were used for Codex skill/path facts.
- `opencode --help`, `opencode run --help`, `opencode models --help`, `opencode models --refresh`, and `opencode models` succeeded when run with access to the user global config.
