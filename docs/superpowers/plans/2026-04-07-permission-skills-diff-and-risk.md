# Permission Skills: Diff + Risk Level Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add danger scanning with red diff lines to `permission-init`, and add risk levels + unified diff to `permission-review`, both using the `yes / no / edit` prompt pattern.

**Architecture:** Two independent markdown skill files change. `permission-init` Step 5 gains a danger scan of existing entries and red `-` lines in the diff. `permission-review` Step 7 gains LOW/MEDIUM/HIGH risk labels and replaces its READY-TO-PASTE block with a unified colored diff. Both skills are AI instructions, not executable code — verification is manual smoke testing.

**Tech Stack:** Markdown (skill instructions), JSON (plugin.json version bump)

---

## File Map

- Modify: `skills/permission-init/SKILL.md` — rewrite Step 5 to add danger scan and red diff lines
- Modify: `skills/permission-review/SKILL.md` — rewrite Step 7 to add risk levels and unified diff
- Modify: `.claude-plugin/plugin.json` — bump patch version (0.1.2 → 0.1.3)

---

### Task 1: Update permission-init Step 5 — danger scan + red diff lines

**Files:**
- Modify: `skills/permission-init/SKILL.md`

- [ ] **Step 1: Read the current file**

Read `skills/permission-init/SKILL.md`. The current Step 5 starts at `## Step 5: Show diff and apply` and runs to the end of the file. Note the exact lines so you can replace precisely.

- [ ] **Step 2: Replace Step 5 with the new version**

Replace everything from `## Step 5: Show diff and apply` to the end of the file with:

~~~markdown
## Step 5: Show diff and apply

1. Read `~/.claude/settings.json`. If it does not exist or has no `permissions` key, start from `{"permissions": {"allow": []}}`.

2. Scan existing `permissions.allow` entries for danger: flag any entry that matches the "always prompt" list from Step 4:
   - `rm`, `rm -rf`, or any destructive delete pattern
   - `git push` (any remote operation)
   - `curl`, `wget` to external hosts
   - `docker push` (registry operations)
   - Anything touching `~/.ssh`, `~/.aws`, `~/.gnupg`
   - Database migration commands (`migrate`, `alembic`, `prisma migrate deploy`)

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

5. Prompt: **`Apply? (yes / no / edit)`**
   - `yes` — remove flagged dangerous entries AND merge net-new entries into `permissions.allow` (no duplicates), write back to `~/.claude/settings.json`
   - `no` — leave as-is, done
   - `edit` — ask: "Which entries do you want to add, remove, or rename?" Accept natural language (e.g. "keep curl, drop git add"). Apply the requested changes to the proposed diff (both additions and removals), re-display the updated diff, then prompt: `Apply? (yes / no)` — no further edit loop.
~~~

- [ ] **Step 3: Verify the edit**

Read `skills/permission-init/SKILL.md` and confirm:
- Step 5 heading still reads `## Step 5: Show diff and apply`
- Step 5 now has a "Scan existing entries for danger" numbered item (item 2)
- The diff example shows red `-` lines with `DANGEROUS` label
- The `yes` branch mentions both removing flagged entries AND merging new ones
- Steps 1–4 and the pattern convention note in Step 4 are completely unchanged

- [ ] **Step 4: Commit**

```bash
git add skills/permission-init/SKILL.md
git commit -m "feat: permission-init flags dangerous existing entries with red diff lines"
```

---

### Task 2: Update permission-review Step 7 — risk levels + unified diff

**Files:**
- Modify: `skills/permission-review/SKILL.md`

- [ ] **Step 1: Read the current file**

Read `skills/permission-review/SKILL.md`. Locate `## Step 7: Output recommendations` — it runs from that heading to just before `## Step 8`. Note the exact line range.

- [ ] **Step 2: Replace Step 7 with the new version**

Replace everything from `## Step 7: Output recommendations` up to (but not including) `## Step 8: Mark entries as reviewed` with:

~~~markdown
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
~~~

- [ ] **Step 3: Verify the edit**

Read `skills/permission-review/SKILL.md` and confirm:
- Step 7 now contains a "Risk levels" section with LOW/MEDIUM/HIGH definitions and examples
- The FRICTION section format shows `[LOW/MEDIUM/HIGH — reason]` labels
- The OVER-PERMISSIVE section format shows `[LOW/MEDIUM/HIGH — reason]` labels
- The READY-TO-PASTE jsonc block is gone
- A unified `diff` code block is present showing both `+` and `-` lines with risk in comments
- The prompt reads `Apply? (yes / no / edit)` — `show me first` is gone
- Step 8 is completely unchanged

- [ ] **Step 4: Commit**

```bash
git add skills/permission-review/SKILL.md
git commit -m "feat: permission-review adds risk levels and unified diff with yes/no/edit prompt"
```

---

### Task 3: Bump plugin version

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Update the version field**

In `.claude-plugin/plugin.json`, change:
```json
"version": "0.1.2"
```
to:
```json
"version": "0.1.3"
```

- [ ] **Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 0.1.3"
```

---

### Task 4: Smoke test

**No automated tests — verification is manual.**

- [ ] **Step 1: Reinstall the plugin**

In a Claude Code session:
```
/plugin install permission-pilot
/reload-plugins
```

- [ ] **Step 2: Smoke test permission-init danger scan**

Temporarily add a dangerous entry to `~/.claude/settings.json`:
```json
"Bash(rm:*)"
```

Then run `/permission-init` in any project directory. Verify:
- [ ] A red `-` line appears for `Bash(rm:*)` with a `DANGEROUS` label
- [ ] Net-new safe entries appear as green `+` lines
- [ ] The `yes` option removes the dangerous entry AND adds new ones
- [ ] Remove the test entry if you answered `no`

- [ ] **Step 3: Smoke test permission-review risk levels**

Run `/permission-review` in a project with enough log data (5+ entries). Verify:
- [ ] FRICTION entries show `[LOW/MEDIUM/HIGH — reason]` labels
- [ ] OVER-PERMISSIVE entries show `[LOW/MEDIUM/HIGH — reason]` labels
- [ ] A unified `diff` block appears (no READY-TO-PASTE block)
- [ ] The prompt reads `Apply? (yes / no / edit)` — no `show me first` option
