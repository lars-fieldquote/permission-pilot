# permission-init Improvements — Design Spec

**Date:** 2026-04-06  
**Status:** Approved

## Summary

Three focused improvements to the `permission-init` skill:

1. Show a colored diff automatically (no "show me first" option needed)
2. Replace `yes / show me first / no` prompt with `yes / no / edit`
3. Standardize all generated patterns to colon syntax (`Bash(git diff:*)`)

Steps 1–4 of the skill are unchanged. Only Step 5 is rewritten.

## Changes

### Step 5: Show diff and apply

**Previous behavior:**
- Output a ready-to-paste jsonc block
- Ask: "Want me to merge this into your `~/.claude/settings.json` now? (yes / show me first / no)"
- "show me first" displayed the full updated permissions block, then asked yes/no

**New behavior:**

1. Read `~/.claude/settings.json` (start from `{"permissions": {"allow": []}}` if absent or no permissions key)
2. Compute net-new entries: generated list minus entries already covered by existing rules
   - Skip exact matches
   - Skip entries subsumed by a more general existing pattern (e.g. existing `Bash(git:*)` covers `Bash(git diff:*)`)
3. Show a colored terminal diff — green `+` lines for additions, existing entries noted as skipped:

```diff
  permissions.allow (current → proposed)

+ "Bash(git status:*)",     // safe: read-only git
+ "Bash(git log:*)",        // safe: read-only git
+ "Bash(git add:*)",        // safe: local git staging
  "Bash(git diff:*)",       // already present — skipped
```

4. Prompt: **`Apply? (yes / no / edit)`**
   - `yes` — merge new entries into `permissions.allow` and write back
   - `no` — leave as-is
   - `edit` — ask "Which entries do you want to add, remove, or rename?" in natural language, apply the changes, re-show the updated diff, then ask `Apply? (yes / no)` (no further edit loop)

### Pattern convention

All generated entries use `Bash(<command>:*)` colon syntax. This matches the pattern already used in the user's settings and is more precise — it scopes to the subcommand rather than any string starting with the command name.

## Out of scope

- Steps 1–4 are unchanged
- No evidence-only filtering (would be too strict for an inferential skill)
- No per-entry interactive editor (slows the happy path)
- No changes to `permission-review`
