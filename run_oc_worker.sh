#!/usr/bin/env bash
set -euo pipefail

TASK_FILE=".ai/OC_TASK.md"
MODEL="opencode-go/kimi-k2.7-code"
AGENT="build"
PROJECT_DIR="."
TIMEOUT_SEC="1800"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-file)
      TASK_FILE="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --agent)
      AGENT="$2"
      shift 2
      ;;
    --project-dir|--dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --timeout-sec|--timeout)
      TIMEOUT_SEC="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

command -v opencode >/dev/null 2>&1 || { echo "opencode command not found." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git command not found." >&2; exit 1; }
command -v timeout >/dev/null 2>&1 || { echo "timeout command not found. Install coreutils or run opencode manually." >&2; exit 1; }

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

if [[ "$TASK_FILE" = /* ]]; then
  TASK_PATH="$TASK_FILE"
else
  TASK_PATH="$PROJECT_DIR/$TASK_FILE"
fi

[[ -f "$TASK_PATH" ]] || { echo "TaskFile not found: $TASK_PATH" >&2; exit 1; }
git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ProjectDir is not inside a git repository: $PROJECT_DIR" >&2; exit 1; }

echo "Refreshing OpenCode models..."
opencode models --refresh
MODELS="$(opencode models)"

if ! printf '%s\n' "$MODELS" | grep -Fxq "$MODEL"; then
  FALLBACK_MODEL="opencode-go/deepseek-v4-flash"
  echo "Model not found: $MODEL. Falling back to $FALLBACK_MODEL." >&2
  MODEL="$FALLBACK_MODEL"
fi

if ! printf '%s\n' "$MODELS" | grep -Fxq "$MODEL"; then
  echo "Requested model is not available after fallback: $MODEL. Run 'opencode models' and pass --model with an available provider/model." >&2
  exit 1
fi

MESSAGE="Strictly execute the task file. Only modify allowed files. Do not do unrelated refactors. Run requested tests if possible. Report changed files, tests, and blockers."

echo "Running one-shot opencode run with model: $MODEL"
set +e
timeout "$TIMEOUT_SEC" opencode run \
  --agent "$AGENT" \
  --model "$MODEL" \
  --file "$TASK_PATH" \
  --dir "$PROJECT_DIR" \
  "$MESSAGE"
EXIT_CODE=$?
set -e

echo "opencode exit code: $EXIT_CODE"
echo "git status --short:"
git -C "$PROJECT_DIR" status --short
echo "git diff --stat:"
git -C "$PROJECT_DIR" diff --stat

exit "$EXIT_CODE"
