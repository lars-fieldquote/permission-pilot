#!/bin/bash
# permission-pilot: passive hook logger
# Called by PermissionRequest and PreToolUse(Bash) hooks.
# Hook event JSON is received via stdin.
# Fails silently — must never interrupt Claude workflows.
{
  set -euo pipefail

  LOG_FILE="${HOME}/.claude/permission-log.jsonl"

  # Read hook event JSON from stdin
  INPUT=$(cat)

  # Derive trigger from hook_event_name field
  HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""')
  if [[ "$HOOK_EVENT" == "PermissionRequest" ]]; then
    TRIGGER="permission"
  else
    TRIGGER="tool_use"
  fi

  # Extract fields
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
  TOOL_INPUT=$(echo "$INPUT" | jq -r '
    .tool_input.command //
    .tool_input.path //
    (.tool_input | if type == "object" then tojson else (. // "") end)')
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
  PROJECT=$(echo "$INPUT" | jq -r '.cwd // ""')

  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Ensure log directory exists
  mkdir -p "$(dirname "$LOG_FILE")"

  # Append JSONL entry
  jq -cn \
    --arg ts         "$TS" \
    --arg trigger    "$TRIGGER" \
    --arg session_id "$SESSION_ID" \
    --arg project    "$PROJECT" \
    --arg tool       "$TOOL_NAME" \
    --arg input      "$TOOL_INPUT" \
    '{ts: $ts, trigger: $trigger, session_id: $session_id, project: $project, tool: $tool, input: $input, reviewed: false}' \
    >> "$LOG_FILE"
} 2>/dev/null || true
