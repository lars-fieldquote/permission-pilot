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
