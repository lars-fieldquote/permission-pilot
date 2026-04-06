#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAKE_HOME=$(mktemp -d)
export HOME="$FAKE_HOME"

LOG_FILE="$FAKE_HOME/.claude/permission-log.jsonl"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; rm -rf "$FAKE_HOME"; exit 1; }

# --- Test 1: PreToolUse entry is written ---
printf '{"tool_name":"Bash","tool_input":{"command":"npm install"},"session_id":"sess1","cwd":"/test/myproject","hook_event_name":"PreToolUse"}' \
  | bash "$SCRIPT_DIR/hooks/log.sh"

[[ -f "$LOG_FILE" ]] || fail "log file not created at $LOG_FILE"
ENTRY=$(cat "$LOG_FILE")
echo "$ENTRY" | jq -e '.trigger == "tool_use"'        > /dev/null || fail "trigger should be tool_use"
echo "$ENTRY" | jq -e '.tool == "Bash"'               > /dev/null || fail "tool should be Bash"
echo "$ENTRY" | jq -e '.input == "npm install"'       > /dev/null || fail "input should be npm install"
echo "$ENTRY" | jq -e '.project == "/test/myproject"' > /dev/null || fail "project should come from cwd field"
echo "$ENTRY" | jq -e '.session_id == "sess1"'        > /dev/null || fail "session_id field"
echo "$ENTRY" | jq -e '.reviewed == false'             > /dev/null || fail "reviewed should be false"
echo "$ENTRY" | jq -e '.ts | test("^[0-9]{4}-")'      > /dev/null || fail "ts should be ISO timestamp"
pass "PreToolUse entry written with correct fields"

# --- Test 2: PermissionRequest entry is written ---
printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf dist"},"session_id":"sess2","cwd":"/test/myproject","hook_event_name":"PermissionRequest"}' \
  | bash "$SCRIPT_DIR/hooks/log.sh"

ENTRY=$(tail -1 "$LOG_FILE")
echo "$ENTRY" | jq -e '.trigger == "permission"' > /dev/null || fail "trigger should be permission"
echo "$ENTRY" | jq -e '.input == "rm -rf dist"'  > /dev/null || fail "input should be rm -rf dist"
pass "PermissionRequest entry written with correct trigger"

# --- Test 3: Multiple entries append (not overwrite) ---
LINE_COUNT=$(wc -l < "$LOG_FILE")
[[ "$LINE_COUNT" -eq 2 ]] || fail "expected 2 lines in log, got $LINE_COUNT"
pass "Entries appended, not overwritten"

# --- Test 4: Each line is valid JSON ---
while IFS= read -r line; do
  echo "$line" | jq . > /dev/null || fail "invalid JSON: $line"
done < "$LOG_FILE"
pass "All log entries are valid JSON"

# --- Test 5: Log dir created if missing ---
FAKE_HOME2=$(mktemp -d)
export HOME="$FAKE_HOME2"
printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"sess3","cwd":"/test/other","hook_event_name":"PreToolUse"}' \
  | bash "$SCRIPT_DIR/hooks/log.sh"
[[ -f "$FAKE_HOME2/.claude/permission-log.jsonl" ]] || fail "log dir not auto-created"
pass "Log directory auto-created when missing"

rm -rf "$FAKE_HOME" "$FAKE_HOME2"
echo ""
echo "All tests passed."
