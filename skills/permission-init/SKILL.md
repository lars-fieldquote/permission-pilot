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

Note: For `hardened` posture, skip questions about deploy scripts and Docker registries — these commands always prompt regardless of the answers.

## Step 4: Generate the allow-list

Based on stack + posture + interview answers, reason about each command category:

**Always safe (all postures):**
- `git status`, `git diff`, `git log`, `git branch` — read-only git
- `ls`, `cat`, `echo`, `pwd` — read-only filesystem inspection
- Package manager read operations: `npm list`, `pip list`, `cargo tree`

**Safe for `loose` and `balanced`, prompt for `hardened`:**
(Note: `loose` and `balanced` use identical allow-rules in this skill. The distinction matters more in `/permission-review` which applies looser pattern matching for `loose` posture.)
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

**Pattern convention:** All generated entries must use `Bash(<command>:*)` colon syntax (e.g. `Bash(git status:*)` not `Bash(git status*)`).

## Step 5: Show diff and apply

1. Read `~/.claude/settings.json`. If it does not exist or has no `permissions` key, start from `{"permissions": {"allow": []}}`.

2. Scan existing `permissions.allow` entries for danger: flag any entry that matches the "always prompt" list from Step 4:
   - `rm`, `rm -rf`, or any destructive delete pattern
   - `git push` (any remote operation)
   - `curl`, `wget` to external hosts
   - `docker push` (registry operations)
   - Anything touching `~/.ssh`, `~/.aws`, `~/.gnupg`
   - Database migration commands (`./migrate.sh`, `alembic upgrade`, `prisma migrate deploy`)

   Flagged entries get red `-` lines in the diff with a `DANGEROUS` label.

3. Compute net-new entries: take the generated list and remove any entry already covered by an existing rule:
   - Skip exact matches
   - Skip entries whose command is already subsumed by a broader existing pattern (e.g. existing `Bash(git:*)` covers `Bash(git diff:*)`)

4. Display a diff (use a `diff` code block) showing removals, additions, and skipped entries:

```diff
  permissions.allow (current → proposed)

- "Bash(rm:*)",              // DANGEROUS — always prompt; recommend removing
- "Bash(curl:*)",            // DANGEROUS — always prompt; recommend removing
+ "Bash(git status:*)",      // safe: read-only git
+ "Bash(git add:*)",         // safe: local git staging
  "Bash(git diff:*)",        // already present — skipped

# withheld (always prompt): git push, rm, curl
```

If an entry is both flagged as dangerous AND appears in the generated allow-list, show only the `-` DANGEROUS line — do not re-add it as a `+` line.

5. Prompt: **`Apply? (yes / no / edit)`**
   - `yes` — remove flagged dangerous entries AND merge net-new entries into `permissions.allow` (no duplicates), write back to `~/.claude/settings.json`
   - `no` — leave as-is, done
   - `edit` — ask: "Which entries do you want to add, remove, or rename?" Accept natural language (e.g. "keep curl, drop git add"). Apply the requested changes to the proposed diff (both additions and removals), re-display the updated diff, then prompt: `Apply? (yes / no)` — no further edit loop. If the user chooses to keep a flagged entry, remove its DANGEROUS line from the diff and treat it as an unchanged context line.
