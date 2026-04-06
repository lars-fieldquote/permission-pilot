# Permission Skills: Diff + Risk Level Improvements — Design Spec

**Date:** 2026-04-07  
**Status:** Approved

## Summary

Two skill files change. Both get the same diff-first pattern. `permission-review` also gets risk level indicators on its recommendations.

## Change 1: permission-init — danger check on existing entries

**File:** `skills/permission-init/SKILL.md`

**What changes:** Step 5 gains a danger scan of existing `permissions.allow` entries before showing the diff.

**New Step 5 flow:**

1. Read `~/.claude/settings.json` (already done — no change here)
2. Scan each existing `permissions.allow` entry against the "always prompt" list from Step 4:
   - `rm -rf` or any destructive delete
   - `git push` (any remote operation)
   - `curl`, `wget` to external hosts
   - `docker push` (registry operations)
   - Anything touching `~/.ssh`, `~/.aws`, `~/.gnupg`
   - Database migration commands (`./migrate.sh`, `alembic upgrade`, `prisma migrate deploy`)
3. Existing entries that match get red `-` lines in the diff with a `DANGEROUS` label. Net-new entries get green `+` lines as before. Existing safe entries are noted as skipped.
4. `yes` applies both additions and removals in a single write.

**Diff example:**

```diff
  permissions.allow (current → proposed)

- "Bash(rm:*)",              // DANGEROUS — always prompt; recommend removing
- "Bash(curl:*)",            // DANGEROUS — always prompt; recommend removing
+ "Bash(git status:*)",      // safe: read-only git
+ "Bash(git add:*)",         // safe: local git staging
  "Bash(git diff:*)",        // already present — skipped

# withheld (always prompt): git push, rm, curl
```

**Prompt:** `Apply? (yes / no / edit)` — unchanged from the prior improvement.

---

## Change 2: permission-review — diff + risk levels

**File:** `skills/permission-review/SKILL.md`

**What changes:** Step 7 output is restructured. The analysis sections (FRICTION, OVER-PERMISSIVE) gain LOW/MEDIUM/HIGH risk labels. The READY-TO-PASTE jsonc block is replaced with a unified colored diff. The `yes / show me first / no` prompt is replaced with `Apply? (yes / no / edit)`.

### Risk level definitions

Apply these levels when labeling FRICTION and OVER-PERMISSIVE entries:

**LOW** — read-only, no side effects, no network, no file mutation  
Examples: `npm test`, `cargo build`, `git log`, `ls`

**MEDIUM** — writes to local state, exposes local ports, or runs scripts with limited blast radius  
Examples: `docker-compose up`, `npm run build`, `make`, `pip install`

**HIGH** — network access, production-touching scripts, broad patterns, credential-adjacent paths  
Examples: `./deploy.sh`, `psql`, `npm run *` (overly broad), `./scripts/*`

### Updated FRICTION section format

```
FRICTION (consider allowing — blocked N times in last 30 days):
  npm test          blocked 12x  → Bash(npm test:*)           [LOW — standard test runner]
  docker-compose up blocked  8x  → Bash(docker-compose up:*)  [MEDIUM — exposes network ports]
  ./deploy.sh       blocked  3x  → Bash(./deploy.sh:*)        [HIGH — may touch production]
```

### Updated OVER-PERMISSIVE section format

```
OVER-PERMISSIVE (consider removing or tightening):
  Bash(curl:*)   never triggered in 30 days                   [HIGH — unrestricted network]
  Bash(npm run:*) triggered but pattern too broad for balanced [MEDIUM — tighten to npm run test*]
```

### Unified diff (replaces READY-TO-PASTE block)

```diff
  permissions.allow (current → proposed)

+ "Bash(npm test:*)",            // friction: 12x blocked | LOW risk
+ "Bash(docker-compose up:*)",   // friction: 8x blocked | MEDIUM risk
- "Bash(curl:*)",                // over-permissive: never triggered | HIGH risk
- "Bash(npm run:*)",             // over-permissive: too broad for balanced | MEDIUM risk

# still prompting: git push, rm, curl, docker push
```

### Prompt

Replace `"Apply these changes to ~/.claude/settings.json? (yes / show me first / no)"` with:

`Apply? (yes / no / edit)`
- `yes` — apply adds and removes, write back to `~/.claude/settings.json`
- `no` — leave as-is, done
- `edit` — ask: "Which entries do you want to add, remove, or rename?" Accept natural language. Apply changes, re-show updated diff, then prompt `Apply? (yes / no)` — no further edit loop.

Remove the `show me first` branch entirely.

---

## Out of scope

- Steps 1–6 of `permission-review` are unchanged
- Steps 1–4 of `permission-init` are unchanged
- No changes to posture logic, log pruning, or interview questions
- No changes to `permission-review` Step 8 (mark entries as reviewed)
