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
- Unless `--all-projects` was passed, filter to entries where `project` matches the current working directory
- Unless `--days N` was passed, filter to entries from the last 30 days
- Exclude entries where `reviewed == true`

If fewer than 5 unreviewed entries remain after filtering, say: "Not enough log data yet for this project (N entries). Keep working and run /permission-review again in a few days." Then stop.

## Step 3: Load current settings

Read `~/.claude/settings.json`. Extract the `permissions.allow` array (may be empty or absent).

## Step 4: Identify friction

From the log entries with `trigger == "permission"` (or all entries if PermissionRequest does not fire in bypass mode — in that case all entries have `trigger == "tool_use"`):

Group commands by pattern (strip arguments to find the base command, e.g. `npm install express` → `npm install`). Count occurrences per pattern.

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
