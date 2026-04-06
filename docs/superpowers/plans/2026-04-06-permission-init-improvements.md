# permission-init Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve `permission-init` Step 5 to show a colored diff automatically, replace the three-way prompt with `yes / no / edit`, and standardize all generated patterns to colon syntax.

**Architecture:** Only `skills/permission-init/SKILL.md` changes — Steps 1–4 are untouched. Step 5 is rewritten in place. The skill is AI instructions (markdown), not executable code, so verification is a manual smoke test rather than an automated unit test.

**Tech Stack:** Markdown (skill instructions), JSON (plugin.json version bump)

---

## File Map

- Modify: `skills/permission-init/SKILL.md` — rewrite Step 5 only
- Modify: `.claude-plugin/plugin.json` — bump patch version (0.1.1 → 0.1.2)

---

### Task 1: Rewrite Step 5 in the skill

**Files:**
- Modify: `skills/permission-init/SKILL.md`

- [ ] **Step 1: Open and read the current Step 5**

Read `skills/permission-init/SKILL.md` and locate the `## Step 5: Output the allow-list` section (currently lines 67–88).

- [ ] **Step 2: Replace Step 5 with the new version**

Replace the entire `## Step 5` section with the following:

```markdown
## Step 5: Show diff and apply

1. Read `~/.claude/settings.json`. If it does not exist or has no `permissions` key, start from `{"permissions": {"allow": []}}`.

2. Compute net-new entries: take the generated list and remove any entry already covered by an existing rule:
   - Skip exact matches
   - Skip entries whose command is already subsumed by a broader existing pattern (e.g. existing `Bash(git:*)` covers `Bash(git diff:*)`)

3. Display a colored diff showing what will be added. Use `+` prefix for new entries and a note for skipped ones:

```diff
  permissions.allow (current → proposed)

+ "Bash(git status:*)",     // safe: read-only git
+ "Bash(git log:*)",        // safe: read-only git
+ "Bash(git add:*)",        // safe: local git staging
  "Bash(git diff:*)",       // already present — skipped
```

4. Prompt: **`Apply? (yes / no / edit)`**
   - `yes` — merge net-new entries into `permissions.allow` (no duplicates), write back to `~/.claude/settings.json`
   - `no` — leave as-is, done
   - `edit` — ask: "Which entries do you want to add, remove, or rename?" Accept natural language (e.g. "drop jq, rename the hooks entry to Bash(bash:*)"). Apply the requested changes to the net-new list, re-display the updated diff, then prompt: `Apply? (yes / no)` — no further edit loop.

**Pattern convention:** All generated entries use `Bash(<command>:*)` colon syntax (e.g. `Bash(git status:*)` not `Bash(git status*)`). This matches the precision of typical existing entries and scopes the rule to the subcommand.
```

- [ ] **Step 3: Verify the edit looks correct**

Read `skills/permission-init/SKILL.md` and confirm:
- Step 5 heading reads `## Step 5: Show diff and apply`
- The old "ready-to-paste block" and `yes / show me first / no` prompt are gone
- The diff display block, `yes / no / edit` prompt, and pattern convention note are all present
- Steps 1–4 are unchanged

- [ ] **Step 4: Commit**

```bash
git add skills/permission-init/SKILL.md
git commit -m "feat: permission-init shows diff upfront, yes/no/edit prompt, colon pattern syntax"
```

---

### Task 2: Bump plugin version

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Update the version field**

In `.claude-plugin/plugin.json`, change:
```json
"version": "0.1.1"
```
to:
```json
"version": "0.1.2"
```

- [ ] **Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 0.1.2"
```

---

### Task 3: Smoke test

**No automated test exists for skill instructions — verification is manual.**

- [ ] **Step 1: Reinstall the plugin**

In a Claude Code session, run:
```
/plugin install permission-pilot
/reload-plugins
```

- [ ] **Step 2: Run the skill in the permission-pilot project directory**

```
/permission-init
```

- [ ] **Step 3: Verify the new behavior**

Check all of the following:
- [ ] The skill reads `~/.claude/settings.json` before prompting anything
- [ ] A diff block appears automatically (no "show me first" option was offered)
- [ ] Entries already in `permissions.allow` are shown as skipped, not as additions
- [ ] Generated entries use `Bash(<command>:*)` colon syntax
- [ ] The prompt reads `Apply? (yes / no / edit)` — not `yes / show me first / no`
- [ ] Typing `edit` triggers a follow-up question asking which entries to change
- [ ] After edit, the updated diff is shown before final `yes / no` confirmation
