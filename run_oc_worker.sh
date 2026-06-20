#!/usr/bin/env bash
set -euo pipefail

TASK_FILE=".ai/OC_TASK.md"
MODEL=""
PROVIDER_PREFERENCE="opencode-go,opencode,copilot,github-copilot,gemini,google"
ALLOW_FREE_FALLBACK="true"
ALLOW_PAID_FALLBACK="false"
MODEL_INTENT="auto"
AGENT="auto"
MODE="USER_TASK"
PROJECT_DIR="."
TIMEOUT_SEC="1800"
DRY_RUN="false"

show_help() {
  cat <<'HELP'
opencode-go-worker Bash wrapper

Runs one short-lived opencode run. Codex decides whether to run another round.

Options:
  --task-file PATH
  --model PROVIDER/MODEL
  --provider-preference CSV
  --allow-free-fallback true|false
  --allow-paid-fallback
  --model-intent auto|small|coding|hard|review|docs
  --agent auto|build|plan|explore|scout
  --mode USER_TASK|MAINTAIN_SKILL
  --project-dir PATH
  --timeout-sec SECONDS
  --dry-run
  --help
HELP
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-file) TASK_FILE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --provider-preference) PROVIDER_PREFERENCE="$2"; shift 2 ;;
    --allow-free-fallback) ALLOW_FREE_FALLBACK="$2"; shift 2 ;;
    --allow-paid-fallback) ALLOW_PAID_FALLBACK="true"; shift ;;
    --model-intent) MODEL_INTENT="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --project-dir|--dir) PROJECT_DIR="$2"; shift 2 ;;
    --timeout-sec|--timeout) TIMEOUT_SEC="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) fail "Unknown argument: $1" 2 ;;
  esac
done

case "$MODEL_INTENT" in auto|small|coding|hard|review|docs) ;; *) fail "Invalid --model-intent: $MODEL_INTENT" 2 ;; esac
case "$AGENT" in auto|build|plan|explore|scout) ;; *) fail "Invalid --agent: $AGENT" 2 ;; esac
case "$MODE" in USER_TASK|MAINTAIN_SKILL) ;; *) fail "Invalid --mode: $MODE" 2 ;; esac

command -v opencode >/dev/null 2>&1 || fail "opencode command not found."
command -v git >/dev/null 2>&1 || fail "git command not found."
command -v timeout >/dev/null 2>&1 || fail "timeout command not found. Install coreutils or run opencode manually."

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "ProjectDir is not inside a git repository: $PROJECT_DIR"

looks_like_plugin_repo() {
  local path="$1"
  local leaf
  leaf="$(basename "$path")"
  [[ "$leaf" =~ [Oo]pencode-[Gg]o-[Ww]orker|codex-opencode-worker ]] && return 0
  [[ -f "$path/SKILL.md" && -f "$path/run_oc_worker.ps1" ]] && return 0
  if [[ -f "$path/README.md" ]] && head -n 20 "$path/README.md" | grep -qi "opencode-go-worker"; then
    return 0
  fi
  return 1
}

if [[ "$MODE" == "USER_TASK" ]] && looks_like_plugin_repo "$PROJECT_DIR"; then
  if [[ "$DRY_RUN" == "true" ]]; then
    cat >&2 <<'ERR'
dry run warning: real execution would be refused. Current directory looks like the opencode-go-worker plugin repository.
USER_TASK mode cannot run OpenCode inside the plugin repo.
Switch to the target project directory, or rerun in MAINTAIN_SKILL mode.
ERR
  else
    cat >&2 <<'ERR'
Current directory looks like the opencode-go-worker plugin repository.
USER_TASK mode cannot run OpenCode inside the plugin repo.
Switch to the target project directory, or rerun in MAINTAIN_SKILL mode.
ERR
    exit 1
  fi
fi

if [[ "$TASK_FILE" = /* ]]; then
  TASK_PATH="$TASK_FILE"
else
  TASK_PATH="$PROJECT_DIR/$TASK_FILE"
fi

if [[ "$DRY_RUN" != "true" && ! -f "$TASK_PATH" ]]; then
  fail "TaskFile not found: $TASK_PATH"
fi

provider_of() {
  local model_name="$1"
  printf '%s' "${model_name%%/*}"
}

intent_patterns() {
  case "$1" in
    small|docs|review) printf '%s\n' flash mini lite fast small ;;
    coding) printf '%s\n' code coder k2 deepseek qwen glm ;;
    hard) printf '%s\n' code coder k2 deepseek qwen glm ;;
    *) printf '%s\n' code coder k2 deepseek qwen glm flash mini fast ;;
  esac
}

select_by_intent() {
  local intent="$1"
  shift
  local candidates=("$@")
  local pool=("${candidates[@]}")
  local filtered=()

  if [[ ${#pool[@]} -eq 0 ]]; then
    return 1
  fi

  if [[ "$intent" == "hard" ]]; then
    for item in "${pool[@]}"; do
      if [[ ! "$item" =~ (flash|mini|lite) ]]; then
        filtered+=("$item")
      fi
    done
    if [[ ${#filtered[@]} -gt 0 ]]; then
      pool=("${filtered[@]}")
    fi
  fi

  while IFS= read -r pattern; do
    for item in "${pool[@]}"; do
      if [[ "$item" =~ $pattern ]]; then
        printf '%s' "$item"
        return 0
      fi
    done
  done < <(intent_patterns "$intent")

  printf '%s' "${pool[0]}"
}

model_exists() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

resolve_agent() {
  if [[ "$AGENT" != "auto" ]]; then
    SELECTED_AGENT="$AGENT"
    AGENT_REASON="explicit agent"
    return
  fi
  if [[ "$MODEL_INTENT" == "review" ]]; then
    SELECTED_AGENT="plan"
    AGENT_REASON="auto review maps to plan"
  else
    SELECTED_AGENT="build"
    AGENT_REASON="auto edit/docs/coding maps to build"
  fi
}

echo "Refreshing OpenCode models..."
opencode models --refresh
mapfile -t MODELS < <(opencode models | awk '/^[^[:space:]\/]+\/[^[:space:]]+$/ { print $0 }')

if [[ -n "$MODEL" ]]; then
  if model_exists "$MODEL" "${MODELS[@]}"; then
    SELECTED_MODEL="$MODEL"
    SELECTED_PROVIDER="$(provider_of "$MODEL")"
    SELECTION_REASON="explicit model exists"
    FALLBACK_USED="false"
  else
    fail "Explicit model not found in opencode models: $MODEL"
  fi
else
  IFS=',' read -r -a PREFS <<< "$PROVIDER_PREFERENCE"
  FREE_PROVIDERS=(opencode-go opencode copilot github-copilot gemini google)
  PAID_PROVIDERS=(openai anthropic openrouter deepseek qwen zhipu moonshot)
  SELECTED_MODEL=""
  SELECTED_PROVIDER=""
  SELECTION_REASON=""
  FALLBACK_USED="false"

  is_free_provider() { local p="$1"; local x; for x in "${FREE_PROVIDERS[@]}"; do [[ "$x" == "$p" ]] && return 0; done; return 1; }
  is_paid_provider() { local p="$1"; local x; for x in "${PAID_PROVIDERS[@]}"; do [[ "$x" == "$p" ]] && return 0; done; return 1; }

  for raw_provider in "${PREFS[@]}"; do
    provider="$(printf '%s' "$raw_provider" | xargs)"
    [[ -z "$provider" ]] && continue
    if [[ "$provider" != "opencode-go" ]] && is_free_provider "$provider" && [[ "$ALLOW_FREE_FALLBACK" != "true" ]]; then
      continue
    fi
    if is_paid_provider "$provider" && [[ "$ALLOW_PAID_FALLBACK" != "true" ]]; then
      continue
    fi

    candidates=()
    for item in "${MODELS[@]}"; do
      [[ "$item" == "$provider/"* ]] && candidates+=("$item")
    done
    if [[ ${#candidates[@]} -gt 0 ]]; then
      SELECTED_MODEL="$(select_by_intent "$MODEL_INTENT" "${candidates[@]}")"
      SELECTED_PROVIDER="$provider"
      if [[ "$provider" == "opencode-go" ]]; then
        SELECTION_REASON="preferred opencode-go provider matched intent '$MODEL_INTENT'"
        FALLBACK_USED="false"
      else
        SELECTION_REASON="fallback provider '$provider' matched intent '$MODEL_INTENT'"
        FALLBACK_USED="true"
      fi
      break
    fi
  done

  if [[ -z "$SELECTED_MODEL" && "$ALLOW_PAID_FALLBACK" == "true" ]]; then
    for provider in "${PAID_PROVIDERS[@]}"; do
      candidates=()
      for item in "${MODELS[@]}"; do
        [[ "$item" == "$provider/"* ]] && candidates+=("$item")
      done
      if [[ ${#candidates[@]} -gt 0 ]]; then
        SELECTED_MODEL="$(select_by_intent "$MODEL_INTENT" "${candidates[@]}")"
        SELECTED_PROVIDER="$provider"
        SELECTION_REASON="paid fallback allowed and provider '$provider' matched intent '$MODEL_INTENT'"
        FALLBACK_USED="true"
        break
      fi
    done
  fi

  [[ -n "$SELECTED_MODEL" ]] || fail "No acceptable model found. Run 'opencode models' or pass --model with a visible provider/model. Paid providers require --allow-paid-fallback."
fi

resolve_agent
MESSAGE="Strictly execute the task file. Only modify allowed files. Do not do unrelated refactors. Do not commit or push. Run requested tests if possible. Report changed files, tests, blockers, and summary."
CMD=(opencode run --agent "$SELECTED_AGENT" --model "$SELECTED_MODEL" --file "$TASK_PATH" --dir "$PROJECT_DIR" "$MESSAGE")

echo "selected model: $SELECTED_MODEL"
echo "selected provider: $SELECTED_PROVIDER"
echo "selection reason: $SELECTION_REASON"
echo "fallback used: $FALLBACK_USED"
echo "selected agent: $SELECTED_AGENT"
echo "agent reason: $AGENT_REASON"
printf 'command:'
printf ' %q' "${CMD[@]}"
printf '\n'

if [[ "$DRY_RUN" == "true" ]]; then
  echo "dry run: opencode run was not executed."
  exit 0
fi

set +e
timeout "$TIMEOUT_SEC" "${CMD[@]}"
EXIT_CODE=$?
set -e

echo "opencode exit code: $EXIT_CODE"
echo "git status --short:"
git -C "$PROJECT_DIR" status --short
echo "git diff --stat:"
git -C "$PROJECT_DIR" diff --stat

exit "$EXIT_CODE"

