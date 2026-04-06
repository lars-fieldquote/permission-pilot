# Skill Structure Fix & Posture Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the permission-pilot plugin so `/permission-init` and `/permission-review` register correctly, and default to `balanced` posture when no config exists.

**Architecture:** Two skill files move from flat `skills/<name>.md` to the required `skills/<name>/SKILL.md` subdirectory structure. Both skills get their "ask for posture" block replaced with a silent `balanced` default that saves to `~/.claude/permission-pilot.json`.

**Tech Stack:** Markdown skill files, Claude Code plugin system

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `skills/permission-init.md` | Delete | Replaced by subdirectory |
| `skills/permission-init/SKILL.md` | Create | `/permission-init` skill with posture default |
| `skills/permission-review.md` | Delete | Replaced by subdirectory |
| `skills/permission-review/SKILL.md` | Create | `/permission-review` skill with posture default |

---

## Task 1: Restructure permission-init skill

**Files:**
- Create: `skills/permission-init/SKILL.md`
- Delete: `skills/permission-init.md`

- [ ] **Step 1: Create `skills/permission-init/SKILL.md`**

Create the file at the new path with the posture default applied. The only change from the original is in Step 1 — the "if neither exists" block replaces the interactive question with a silent default.

```markdown
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
- Default to `balanced`, save `{"posture": "balanced", "log_retention_days": 30}` to `~/.claude/permission-pilot.json`
- Include this note in the output: "No posture config found — defaulting to balanced (saved to `~/.claude/permission-pilot.json`). To change globally, ask: 'set my permission-pilot posture to hardened'. To override for this project only, ask: 'set this project's posture to hardened'."

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
- If "show me first": display the full updated permissions block, then ask: "Apply these changes? (yes / no)"
- If no: leave as-is
```

- [ ] **Step 2: Delete the old flat file**

```bash
git rm skills/permission-init.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/permission-init/SKILL.md
git commit -m "feat: restructure permission-init to skills/permission-init/SKILL.md, default posture to balanced"
```

---

## Task 2: Restructure permission-review skill

**Files:**
- Create: `skills/permission-review/SKILL.md`
- Delete: `skills/permission-review.md`

- [ ] **Step 1: Create `skills/permission-review/SKILL.md`**

Create the file at the new path with the posture default applied. The only change from the original is in Step 1 — the "if neither exists" block replaces the interactive question with a silent default.

```markdown
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
- Database migration commands (`./migrate.sh`, `alembic upgrade`, `prisma migrate deploy`)

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
- If "show me first": display the full updated file, then ask: "Apply these changes? (yes / no)"
- If no: leave as-is

## Step 8: Mark entries as reviewed

If the user applied changes: rewrite `~/.claude/permission-log.jsonl`, setting `reviewed: true` on every entry whose command pattern was included in the recommendations (both friction and over-permissive). These entries will not surface in future reviews unless new instances appear.
```

- [ ] **Step 2: Delete the old flat file**

```bash
git rm skills/permission-review.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/permission-review/SKILL.md
git commit -m "feat: restructure permission-review to skills/permission-review/SKILL.md, default posture to balanced"
```

---

## Task 3: Reinstall plugin and smoke test

**Files:** None

- [ ] **Step 1: Reinstall the plugin**

In Claude Code, run:
```
/plugin install permission-pilot
```

When prompted where to install, choose the same scope as before (local to this repo or user-level). Expected: "Installed permission-pilot."

- [ ] **Step 2: Reload plugins**

```
/reload-plugins
```

- [ ] **Step 3: Verify `/permission-init` registers**

Type `/permission-init` in Claude Code. Expected: skill loads and begins running (reads project files, outputs allow-list with "defaulting to balanced" note). If "Unknown skill" still appears, the plugin did not reinstall correctly — check the install path with:

```bash
cat ~/.claude/plugins/installed_plugins.json | jq '.plugins["permission-pilot@permission-pilot-marketplace"]'
```

Verify `installPath` points to a path containing `skills/permission-init/SKILL.md`.

- [ ] **Step 4: Verify no posture prompt on first run**

Delete the posture config if it exists, then run `/permission-init` again:

```bash
rm -f ~/.claude/permission-pilot.json
```

Expected: skill proceeds without asking for posture, mentions "defaulting to balanced" in output, and `~/.claude/permission-pilot.json` is created with `{"posture": "balanced", "log_retention_days": 30}`.

- [ ] **Step 5: Final commit**

```bash
git add .
git status  # verify nothing unexpected staged
git commit -m "chore: smoke test complete — skill structure fix verified"
```
