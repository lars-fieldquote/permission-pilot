# permission-pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin that passively logs permission requests and tool usage, then helps users generate and tune a calibrated allow-list via two slash commands.

**Architecture:** A passive bash hook writes JSONL entries to `~/.claude/permission-log.jsonl` on every PermissionRequest and PreToolUse(Bash) event. Two Claude skill files (`permission-init.md`, `permission-review.md`) instruct Claude to reason about the project stack / log data and produce ready-to-paste `settings.json` blocks. A posture config (`~/.claude/permission-pilot.json`) with a per-project override (`.claude/permission-pilot.json`) tunes the aggressiveness of recommendations.

**Tech Stack:** Bash (hook), jq (JSON parsing in hook), Markdown skill files (Claude instructions), JSON config

---

## File Map

| File | Responsibility |
|---|---|
| `.claude-plugin/plugin.json` | Plugin metadata (name, version, author) |
| `.claude-plugin/marketplace.json` | Self-hosted marketplace entry |
| `hooks/hooks.json` | Declares which Claude Code hook events to listen to |
| `hooks/log.sh` | Reads hook event from stdin, appends JSONL entry to log |
| `skills/permission-init.md` | Instructs Claude to read project files + posture, generate allow-list |
| `skills/permission-review.md` | Instructs Claude to read logs + posture + current settings, output tuning recommendations |
| `tests/test_log.sh` | Bash test script for log.sh |
| `tests/verify_hook_format.sh` | One-time script to dump raw hook stdin — delete after Task 2 |
| `README.md` | Install instructions, usage, prior art |

---

## Task 1: Plugin infrastructure

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `hooks/hooks.json`

- [ ] **Step 1: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "permission-pilot",
  "description": "Logs Claude Code tool usage and helps you tune a calibrated allow-list via /permission-init and /permission-review",
  "version": "0.1.0",
  "author": {
    "name": "Lars Herrmann"
  },
  "homepage": "https://github.com/larsherrmann/permission-pilot",
  "repository": "https://github.com/larsherrmann/permission-pilot",
  "license": "MIT",
  "keywords": ["permissions", "allow-list", "security", "logging", "hooks"]
}
```

- [ ] **Step 2: Create `.claude-plugin/marketplace.json`**

```json
{
  "name": "permission-pilot-marketplace",
  "description": "Self-hosted marketplace for permission-pilot",
  "owner": {
    "name": "Lars Herrmann"
  },
  "plugins": [
    {
      "name": "permission-pilot",
      "description": "Logs Claude Code tool usage and helps you tune a calibrated allow-list",
      "version": "0.1.0",
      "source": "./",
      "author": {
        "name": "Lars Herrmann"
      }
    }
  ]
}
```

- [ ] **Step 3: Create `hooks/hooks.json`**

> Note: `PermissionRequest` may not fire in bypass mode — this is verified in Task 2. Both hooks pass a `PERMISSION_PILOT_TRIGGER` env var so `log.sh` knows which event fired.

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "PERMISSION_PILOT_TRIGGER=permission \"${CLAUDE_PLUGIN_ROOT}/hooks/log.sh\"",
            "async": true
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "PERMISSION_PILOT_TRIGGER=tool_use \"${CLAUDE_PLUGIN_ROOT}/hooks/log.sh\"",
            "async": true
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/ hooks/hooks.json
git commit -m "feat: add plugin infrastructure and hook declarations"
```

---

## Task 2: Verify hook input format (assumption test — do this before writing log.sh)

This task has one job: discover exactly what JSON arrives on stdin when a hook fires. Delete the verification script after.

**Files:**
- Create: `tests/verify_hook_format.sh` (delete after this task)

- [ ] **Step 1: Create `tests/verify_hook_format.sh`**

```bash
#!/bin/bash
# Dumps raw stdin to a file so we can inspect hook input format.
# Install temporarily, run a bash command, inspect output, then delete.
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/hook_input_dump.json"
```

- [ ] **Step 2: Temporarily wire this script as the PreToolUse hook**

Edit `hooks/hooks.json` to replace `log.sh` with `tests/verify_hook_format.sh`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/tests/verify_hook_format.sh\"",
            "async": true
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Install the plugin locally**

```bash
# From within a Claude Code session, run:
# /plugin install /home/pesch/development/claude-permission-logger
# Then run any bash command (e.g. "run ls") and check:
cat ~/.claude/hook_input_dump.json | jq .
```

Expected: a JSON object. Record the exact field names for `tool_name`, `tool_input`, and `session_id`.

> Common format based on Claude Code docs:
> `{"session_id": "...", "tool_name": "Bash", "tool_input": {"command": "ls"}}`
> Confirm field names and update Task 3 if they differ.

- [ ] **Step 4: Also test PermissionRequest**

Add `PermissionRequest` to the temp hooks.json (same `verify_hook_format.sh` command), switch to default mode, trigger a permission prompt, inspect the dump. Confirm whether `PermissionRequest` fires in bypass mode.

Document findings here before continuing:

```
# FINDINGS (fill in during Task 2):
# PreToolUse stdin fields: tool_name=___, tool_input.command=___, session_id=___
# PermissionRequest fires in bypass mode: yes / no
# PermissionRequest stdin fields: ___
```

- [ ] **Step 5: Restore hooks.json to original (from Task 1) and delete verify script**

```bash
git checkout hooks/hooks.json
rm tests/verify_hook_format.sh
```

---

## Task 3: Write failing tests for log.sh

**Files:**
- Create: `tests/test_log.sh`

> Tests call `hooks/log.sh` directly with mocked env vars and stdin. No framework needed — pure bash assertions.

- [ ] **Step 1: Create `tests/test_log.sh`**

> Update the `jq` field paths on lines marked `# VERIFY` if Task 2 found different field names than `tool_name` / `tool_input.command` / `session_id`.

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAKE_HOME=$(mktemp -d)
export HOME="$FAKE_HOME"
export PWD="/test/myproject"

LOG_FILE="$FAKE_HOME/.claude/permission-log.jsonl"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; rm -rf "$FAKE_HOME"; exit 1; }

# --- Test 1: PreToolUse entry is written ---
printf '{"tool_name":"Bash","tool_input":{"command":"npm install"},"session_id":"sess1"}' \
  | PERMISSION_PILOT_TRIGGER=tool_use bash "$SCRIPT_DIR/hooks/log.sh"

[[ -f "$LOG_FILE" ]] || fail "log file not created at $LOG_FILE"
ENTRY=$(cat "$LOG_FILE")
echo "$ENTRY" | jq -e '.trigger == "tool_use"'   > /dev/null || fail "trigger should be tool_use"
echo "$ENTRY" | jq -e '.tool == "Bash"'          > /dev/null || fail "tool should be Bash"     # VERIFY
echo "$ENTRY" | jq -e '.input == "npm install"'  > /dev/null || fail "input should be npm install"  # VERIFY
echo "$ENTRY" | jq -e '.project == "/test/myproject"' > /dev/null || fail "project field"
echo "$ENTRY" | jq -e '.session_id == "sess1"'   > /dev/null || fail "session_id field"         # VERIFY
echo "$ENTRY" | jq -e '.reviewed == false'        > /dev/null || fail "reviewed should be false"
echo "$ENTRY" | jq -e '.ts | test("^[0-9]{4}-")'  > /dev/null || fail "ts should be ISO timestamp"
pass "PreToolUse entry written with correct fields"

# --- Test 2: PermissionRequest entry is written ---
printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf dist"},"session_id":"sess2"}' \
  | PERMISSION_PILOT_TRIGGER=permission bash "$SCRIPT_DIR/hooks/log.sh"

ENTRY=$(tail -1 "$LOG_FILE")
echo "$ENTRY" | jq -e '.trigger == "permission"'  > /dev/null || fail "trigger should be permission"
echo "$ENTRY" | jq -e '.input == "rm -rf dist"'   > /dev/null || fail "input should be rm -rf dist"
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
printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"sess3"}' \
  | PERMISSION_PILOT_TRIGGER=tool_use bash "$SCRIPT_DIR/hooks/log.sh"
[[ -f "$FAKE_HOME2/.claude/permission-log.jsonl" ]] || fail "log dir not auto-created"
pass "Log directory auto-created when missing"

rm -rf "$FAKE_HOME" "$FAKE_HOME2"
echo ""
echo "All tests passed."
```

- [ ] **Step 2: Run tests — verify they fail because log.sh doesn't exist yet**

```bash
bash tests/test_log.sh
```

Expected: error like `bash: .../hooks/log.sh: No such file or directory`

- [ ] **Step 3: Commit the failing tests**

```bash
git add tests/test_log.sh
git commit -m "test: add failing tests for log.sh"
```

---

## Task 4: Implement log.sh

**Files:**
- Create: `hooks/log.sh`

> Use the field names confirmed in Task 2. The `# VERIFY` comments below show where to update if they differ from defaults.

- [ ] **Step 1: Create `hooks/log.sh`**

```bash
#!/bin/bash
# permission-pilot: passive hook logger
# Called by PermissionRequest and PreToolUse(Bash) hooks.
# PERMISSION_PILOT_TRIGGER env var is set by hooks.json to "permission" or "tool_use".
set -euo pipefail

LOG_FILE="${HOME}/.claude/permission-log.jsonl"
TRIGGER="${PERMISSION_PILOT_TRIGGER:-tool_use}"

# Read hook event JSON from stdin
INPUT=$(cat)

# Extract fields — update field paths here if Task 2 found different names
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')                           # VERIFY
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // (.tool_input | if type == "object" then tojson else (. // "") end)')  # VERIFY
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')                         # VERIFY

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Append JSONL entry
jq -cn \
  --arg ts         "$TS" \
  --arg trigger    "$TRIGGER" \
  --arg session_id "$SESSION_ID" \
  --arg project    "$PWD" \
  --arg tool       "$TOOL_NAME" \
  --arg input      "$TOOL_INPUT" \
  '{ts: $ts, trigger: $trigger, session_id: $session_id, project: $project, tool: $tool, input: $input, reviewed: false}' \
  >> "$LOG_FILE"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x hooks/log.sh
```

- [ ] **Step 3: Run tests — verify they pass**

```bash
bash tests/test_log.sh
```

Expected output:
```
PASS: PreToolUse entry written with correct fields
PASS: PermissionRequest entry written with correct trigger
PASS: Entries appended, not overwritten
PASS: All log entries are valid JSON
PASS: Log directory auto-created when missing

All tests passed.
```

- [ ] **Step 4: Commit**

```bash
git add hooks/log.sh
git commit -m "feat: implement log.sh hook — appends JSONL entries for PermissionRequest and PreToolUse"
```

---

## Task 5: Write `permission-init` skill

**Files:**
- Create: `skills/permission-init.md`

> This is a Claude skill file — a markdown document that instructs Claude what to do when `/permission-init` is invoked. It is not executed code. The "test" is a manual smoke test after Task 7 (install + run).

- [ ] **Step 1: Create `skills/permission-init.md`**

````markdown
---
name: permission-init
description: Initialize Claude Code permissions for the current project based on stack analysis and your security posture
---

# Permission Init

When this skill is invoked, generate a tailored `permissions.allow` block for the current project.

## Step 1: Load security posture

Check for posture config in this order (first found wins):
1. `.claude/permission-pilot.json` in the current working directory
2. `~/.claude/permission-pilot.json`

If neither exists:
- Ask: "What security posture do you want for this project? (loose / balanced / hardened)"
  - **loose**: solo dev, personal project — minimize interruptions, allow most things
  - **balanced**: reasonable middle ground — allow common safe commands, prompt for risky ones
  - **hardened**: production system or sensitive data — tight control, prompt for anything non-trivial
- Save the answer to `~/.claude/permission-pilot.json` as `{"posture": "<answer>", "log_retention_days": 30}`

## Step 2: Identify the project stack

Read these files if they exist (use Read tool, do not assume):
- `package.json` — Node.js project, note scripts and dependencies
- `yarn.lock` or `pnpm-lock.yaml` — confirms Node.js, note package manager
- `Cargo.toml` — Rust project
- `requirements.txt`, `pyproject.toml`, or `Pipfile` — Python project
- `docker-compose.yml` or `Dockerfile` — containerized, note services
- `Makefile` — custom tasks, read targets
- `.env.example` — hints at external services (databases, APIs)
- `*.tf` files (glob for Terraform) — infrastructure as code
- `go.mod` — Go project

## Step 3: Interview for contextual commands

Before generating the allow-list, ask these questions for contextual commands. Ask them one at a time, only if relevant to the detected stack:

- If deploy scripts or Makefiles present: "Does `make deploy` / `./deploy.sh` ever touch a production or shared environment from this machine?"
- If Docker present: "Is this Docker setup local dev only, or does it push images to a registry?"
- If database migration files present: "Do migrations run automatically or do you trigger them manually?"

## Step 4: Generate the allow-list

Based on stack + posture + interview answers, reason about each command category:

**Always safe (all postures):**
- `git status`, `git diff`, `git log`, `git branch` — read-only git
- `ls`, `cat`, `echo`, `pwd` — read-only filesystem inspection
- Package manager read operations: `npm list`, `pip list`, `cargo tree`

**Safe for `loose` and `balanced`, prompt for `hardened`:**
- `npm install`, `pip install`, `cargo build` — dependency installation
- `npm run <script>`, `make <target>` — project scripts (unless deploy confirmed to touch prod)
- `docker-compose up`, `docker-compose down` — local containers (if confirmed local-only)
- `git add`, `git commit` — local git ops

**Always prompt regardless of posture:**
- `rm -rf` or any destructive delete
- `git push` (any remote operation)
- `curl`, `wget` to external hosts
- `docker push` (registry operations)
- Any command touching `~/.ssh`, `~/.aws`, `~/.gnupg`
- Database migration commands (`./migrate.sh`, `alembic upgrade`, `prisma migrate deploy`)

## Step 5: Output the allow-list

Output a ready-to-paste block with a comment for each entry explaining why it's allowed:

```json
// permission-pilot: generated allow-list
// Project: <detected stack> | Posture: <posture>
// Add to ~/.claude/settings.json → permissions.allow
[
  "Bash(git status*)",     // safe: read-only git
  "Bash(git diff*)",       // safe: read-only git
  "Bash(npm install*)",    // safe: dependency installation
  "Bash(npm run test*)",   // safe: test runner
  ...
]
// Still prompting: rm*, git push*, curl*, docker push*
```

Then ask: "Want me to merge this into your `~/.claude/settings.json` now? (yes / show me first / no)"
- If yes: read `~/.claude/settings.json`, merge the new entries into `permissions.allow` (avoid duplicates), write back
- If "show me first": display the full updated permissions block, then ask again
- If no: leave as-is
````

- [ ] **Step 2: Commit**

```bash
git add skills/permission-init.md
git commit -m "feat: add /permission-init skill"
```

---

## Task 6: Write `permission-review` skill

**Files:**
- Create: `skills/permission-review.md`

- [ ] **Step 1: Create `skills/permission-review.md`**

````markdown
---
name: permission-review
description: Analyze your permission logs and current settings to identify friction points and over-permissive rules
---

# Permission Review

When invoked, analyze the permission log and current settings to produce tuning recommendations.

Accepts optional arguments:
- `--days N` — only consider log entries from the last N days (default: 30)
- `--all-projects` — include entries from all projects (default: current project only)

## Step 1: Load posture config

Check for posture config in this order (first found wins):
1. `.claude/permission-pilot.json` in the current working directory
2. `~/.claude/permission-pilot.json`

If neither exists, ask: "What security posture do you want? (loose / balanced / hardened)" — save to `~/.claude/permission-pilot.json`.

## Step 2: Load and prune logs

Read `~/.claude/permission-log.jsonl`.

**Prune stale entries:** Calculate the cutoff date as today minus `log_retention_days` (default 30, from posture config). Remove all entries older than the cutoff by rewriting the file without them. Only prune during this review — never in the background.

**Filter to scope:**
- Unless `--all-projects` was passed, filter to entries where `project` matches the current working directory (`$PWD`)
- Unless `--days N` was passed, filter to entries from the last 30 days
- Exclude entries where `reviewed == true`

If fewer than 5 unreviewed entries remain after filtering, say: "Not enough log data yet for this project (N entries). Keep working and run /permission-review again in a few days." Then stop.

## Step 3: Load current settings

Read `~/.claude/settings.json`. Extract the `permissions.allow` array (may be empty or absent).

## Step 4: Identify friction

From the log entries with `trigger == "permission"` (or all `trigger == "tool_use"` entries if PermissionRequest does not fire in bypass mode):

Group commands by pattern (strip flags and arguments to find the base command, e.g. `npm install express` → `npm install`). Count occurrences per pattern.

For each pattern with 3+ occurrences that is NOT already in `permissions.allow`:
- Apply posture filter: would this command be safe to allow at the current posture level?
  - **loose**: allow anything that isn't in the "always prompt" list below
  - **balanced**: allow read-only ops and standard build/test commands; prompt for deploy/delete/network
  - **hardened**: only suggest allowing strictly read-only commands
- If safe for posture: add to "Friction" section with count and rationale

**Always prompt regardless of posture (never suggest allowing):**
- `rm -rf` or recursive deletes
- `git push` to any remote
- `curl`, `wget` to external hosts  
- `docker push`
- Anything touching `~/.ssh`, `~/.aws`, `~/.gnupg`

## Step 5: Identify over-permissive rules

For each pattern currently in `permissions.allow`:
- Check if it appears in the last 30 days of logs at all — if not: flag as "never triggered"
- Check if it would be considered risky for the current posture — if so: flag as "risky for your posture"

## Step 6: Interview for ambiguous patterns

For any command that is contextually ambiguous (deploy scripts, migration runners, scripts with unclear names), ask one targeted question:

- "You run `./deploy.sh` regularly — does this ever push to a shared or production environment?"
- "I see `psql` in your logs — is this always against a local dev database?"

Use the answers to move ambiguous patterns into the correct section.

## Step 7: Output recommendations

```
=== Permission Review — <project> | Posture: <posture> ===

FRICTION (consider allowing — blocked N times in last 30 days):
  npm test          ran 47x, blocked 12x  → suggest: Bash(npm test*)
  docker-compose up ran 23x, blocked  8x  → suggest: Bash(docker-compose up*)

OVER-PERMISSIVE (consider removing or tightening):
  Bash(curl*)       → allowed but never triggered in 30 days
  Bash(rm*)         → risky for 'balanced'; consider: Bash(rm ./tmp/*)

READY-TO-PASTE — updated permissions.allow:
[
  ... current entries with changes applied ...
]
```

Then ask: "Apply these changes to `~/.claude/settings.json`? (yes / show me first / no)"
- If yes: read `~/.claude/settings.json`, apply adds and removes, write back
- If "show me first": display the full updated file, then ask again
- If no: leave as-is

## Step 8: Mark entries as reviewed

If the user applied changes: rewrite `~/.claude/permission-log.jsonl`, setting `reviewed: true` on every entry whose command pattern was included in the recommendations (both friction and over-permissive). These entries will not surface in future reviews unless new instances appear.
````

- [ ] **Step 2: Commit**

```bash
git add skills/permission-review.md
git commit -m "feat: add /permission-review skill"
```

---

## Task 7: Write README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

```markdown
# permission-pilot

A Claude Code plugin that passively logs tool usage and helps you generate a calibrated allow-list — so you stop getting interrupted by safe commands without losing visibility on risky ones.

## The problem

Claude Code's permission system has no middle ground: default mode prompts constantly, bypass mode leaves you blind. This plugin learns from your actual workflow and helps you craft a minimal, targeted allow-list.

## What it does

- **Passive logging** — every permission request and bash command is logged to `~/.claude/permission-log.jsonl`. Zero friction, fully async.
- **`/permission-init`** — reads your project files, asks about your security posture (loose / balanced / hardened), and generates a starter allow-list on day 1.
- **`/permission-review`** — analyzes your logs against your current settings and posture. Shows you where you're being blocked unnecessarily and where you're over-permissive.

## Install

```bash
/plugin marketplace add github:larsherrmann/permission-pilot
/plugin install permission-pilot
```

## Usage

**Day 1 — generate a starter allow-list:**
```
/permission-init
```

**After a few days of use — tune your settings:**
```
/permission-review
/permission-review --days 7
/permission-review --all-projects
```

## Security posture

Both commands respect your posture setting:

| Posture | Best for | Behavior |
|---|---|---|
| `loose` | Personal projects, solo dev | Allow most things, prompt only for truly dangerous ops |
| `balanced` | Most users (default) | Allow safe patterns, prompt for deploy/delete/network |
| `hardened` | Production systems, sensitive repos | Tight control, prompt for anything non-trivial |

Set globally: `~/.claude/permission-pilot.json`
Override per project: `.claude/permission-pilot.json`

```json
{ "posture": "balanced", "log_retention_days": 30 }
```

## Log file

`~/.claude/permission-log.jsonl` — one JSON object per line:

```json
{"ts":"2026-04-06T10:23:00Z","trigger":"permission","session_id":"abc","project":"/home/user/myapp","tool":"Bash","input":"npm install","reviewed":false}
```

Entries older than `log_retention_days` are pruned automatically when you run `/permission-review`. Nothing is deleted silently in the background.

## Note on bypass mode

`PermissionRequest` likely does not fire when Claude Code is in bypass/dangerous mode. In that case, the `PreToolUse(Bash)` hook provides coverage — all bash commands are still logged, but the `trigger` field will be `tool_use` rather than `permission`.

## Prior art & inspiration

- [dylancaponi/claude-code-permissions](https://github.com/dylancaponi/claude-code-permissions) — curated deny-list with pre-hook validation. Great static baseline.
- [SpillwaveSolutions/claude_permissions_skill](https://github.com/SpillwaveSolutions/claude_permissions_skill) — pioneered natural language → permission config. Inspired `/permission-init`.

permission-pilot adds persistent logging, posture-aware recommendations, and closed-loop review on top of their ideas.

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install instructions and prior art"
```

---

## Task 8: Smoke test (manual)

No new files. Verify the full plugin works end-to-end.

- [ ] **Step 1: Install the plugin from local path**

In a Claude Code session:
```
/plugin install /home/pesch/development/claude-permission-logger
```

Expected: plugin installs without errors, hooks registered.

- [ ] **Step 2: Trigger a bash command and verify logging**

Ask Claude to run `ls`. Then:
```bash
tail -5 ~/.claude/permission-log.jsonl | jq .
```

Expected: a valid JSON entry with `tool: "Bash"`, `input: "ls"`, `reviewed: false`.

- [ ] **Step 3: Run `/permission-init` in a real project**

Navigate to an existing project (e.g. `/home/pesch/development/fieldquote`), start a Claude Code session, run `/permission-init`. Verify:
- Claude reads project files
- Claude asks about posture if no config exists
- Claude outputs a plausible allow-list for the detected stack
- Offering to merge into `settings.json` works correctly

- [ ] **Step 4: Run `/permission-review` after accumulating a few log entries**

```
/permission-review
```

Verify:
- Claude reads the log
- Friction and over-permissive sections are produced
- The "apply changes" flow works

- [ ] **Step 5: Final commit**

```bash
git add .
git status  # verify nothing unexpected
git commit -m "chore: smoke test complete — v0.1.0 ready"
```
