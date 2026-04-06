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

If neither exists:
- Default to `balanced`, save `{"posture": "balanced", "log_retention_days": 30}` to `~/.claude/permission-pilot.json`
- Note in output: "No posture config found — defaulting to balanced (saved to `~/.claude/permission-pilot.json`). To change globally, ask: 'set my permission-pilot posture to hardened'. To override for this project only, ask: 'set this project's posture to hardened'."

## Step 2: Load and prune logs

Read `~/.claude/permission-log.jsonl`.

**Prune stale entries:** Calculate the cutoff date as today minus `log_retention_days` (default 30, from posture config). Remove all entries older than the cutoff by rewriting the file without them. Only prune during this review — never in the background.

**Filter to scope:**
- Unless `--all-projects` was passed, filter to entries where `project` matches the current working directory
- Unless `--days N` was passed, filter to entries from the last 30 days
- Exclude entries where `reviewed == true`

If fewer than 5 unreviewed entries remain after filtering, say: "Not enough log data yet for this project (N entries). Keep working and run /permission-review again in a few days." Then stop.

## Step 3: Load current settings

Read `~/.claude/settings.json` (if it does not exist or has no `permissions` key, start from `{"permissions": {"allow": []}}`). Extract the `permissions.allow` array.

## Step 4: Identify friction

From the log entries with `trigger == "permission"` (or all entries if PermissionRequest does not fire in bypass mode — in that case all entries have `trigger == "tool_use"`):

Group commands by pattern (strip arguments to find the base command, e.g. `npm install express` → `npm install`). Count occurrences per pattern.

For each pattern with 3+ occurrences that is NOT already in `permissions.allow`:
- Apply posture filter: would this command be safe to allow at the current posture level?
  - **loose**: allow anything that isn't in the "always prompt" list below, using broad patterns (e.g. `npm run *` not `npm run test*`; `./scripts/*` not `./scripts/build*`; wildcard arguments freely)
  - **balanced**: allow read-only ops and standard build/test commands using specific patterns (e.g. `npm run test*`, `npm run build*` — not `npm run *`); prompt for deploy/delete/network
  - **hardened**: only suggest allowing strictly read-only commands
- If safe for posture: add to "Friction" section with count and rationale

**Always prompt regardless of posture (never suggest allowing):**
- `rm -rf` or recursive deletes
- `git push` to any remote
- `curl`, `wget` to external hosts
- `docker push`
- Anything touching `~/.ssh`, `~/.aws`, `~/.gnupg`
- Database migration commands (`./migrate.sh`, `alembic upgrade`, `prisma migrate deploy`)

## Step 5: Identify over-permissive rules

For each pattern currently in `permissions.allow`:
- Check if it appears in the filtered window (default 30 days, or N if `--days N` was passed) — if not: flag as "never triggered"
- Check if it would be considered risky for the current posture — if so: flag as "risky for your posture"

## Step 6: Interview for ambiguous patterns

For any command that is contextually ambiguous (deploy scripts, migration runners, scripts with unclear names), ask one targeted question:

- "You run `./deploy.sh` regularly — does this ever push to a shared or production environment?"
- "I see `psql` in your logs — is this always against a local dev database?"

Note: For `hardened` posture, skip questions about deploy scripts and Docker registries — these commands always prompt regardless of the answers.

Use the answers to move ambiguous patterns into the correct section.

## Step 7: Output recommendations

Output the analysis sections followed by a unified diff.

### Risk levels

Use these levels when labeling FRICTION and OVER-PERMISSIVE entries:

**LOW** — read-only, no side effects, no network, no file mutation  
Examples: `npm test`, `cargo build`, `git log`, `ls`

**MEDIUM** — writes to local state, exposes local ports, or runs scripts with limited blast radius  
Examples: `docker-compose up`, `npm run build`, `make`, `pip install`

**HIGH** — network access, production-touching scripts, broad patterns, credential-adjacent paths  
Examples: `./deploy.sh`, `psql`, `npm run *` (overly broad), `./scripts/*`

### Analysis output

```
=== Permission Review — <project> | Posture: <posture> ===

FRICTION (consider allowing — blocked N times in last 30 days):
  npm test          blocked 12x  → Bash(npm test:*)           [LOW — standard test runner]
  docker-compose up blocked  8x  → Bash(docker-compose up:*)  [MEDIUM — exposes network ports]
  ./deploy.sh       blocked  3x  → Bash(./deploy.sh:*)        [HIGH — may touch production]

OVER-PERMISSIVE (consider removing or tightening):
  Bash(curl:*)    never triggered in 30 days                   [HIGH — unrestricted network]
  Bash(npm run:*) triggered but pattern too broad for balanced  [MEDIUM — tighten to npm run test:*]
```

### Unified diff

Display a diff (use a `diff` code block) showing all proposed changes in one view. `+` lines are friction additions, `-` lines are over-permissive removals. Include the risk level in each comment:

```diff
  permissions.allow (current → proposed)

+ "Bash(npm test:*)",            // friction: 12x blocked | LOW risk
+ "Bash(docker-compose up:*)",   // friction: 8x blocked | MEDIUM risk
- "Bash(curl:*)",                // over-permissive: never triggered | HIGH risk
- "Bash(npm run:*)",             // over-permissive: too broad for balanced | MEDIUM risk

# still prompting: git push, rm, curl, docker push
```

### Prompt

**`Apply? (yes / no / edit)`**
- `yes` — apply adds and removes, write back to `~/.claude/settings.json`
- `no` — leave as-is, done
- `edit` — ask: "Which entries do you want to add, remove, or rename?" Accept natural language (e.g. "keep curl, drop docker-compose"). Apply changes, re-show updated diff, then prompt: `Apply? (yes / no)` — no further edit loop.

## Step 8: Mark entries as reviewed

If the user applied changes: rewrite `~/.claude/permission-log.jsonl`, setting `reviewed: true` on every entry whose command pattern was included in the recommendations (both friction and over-permissive). These entries will not surface in future reviews unless new instances appear.
