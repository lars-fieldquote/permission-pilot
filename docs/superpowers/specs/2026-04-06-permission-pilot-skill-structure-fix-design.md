# Design: Permission Pilot — Skill Structure Fix & Posture Default

**Date:** 2026-04-06  
**Status:** Approved

## Problem

Two issues discovered during smoke testing:

1. **Skills not registering** — skill files are at `skills/permission-init.md` (flat files). Claude Code requires `skills/<name>/SKILL.md` (subdirectory with `SKILL.md`). The plugin installs without error but `/permission-init` and `/permission-review` give "Unknown skill".

2. **Posture friction on first run** — when no posture config exists, both skills ask an interactive question before doing any work. This blocks first-run usefulness and is unnecessary given `balanced` is the obvious default.

---

## Change 1: Skill Structure

**What:** Move both skill files into subdirectories matching the `skills/<name>/SKILL.md` pattern.

```
Before:
  skills/permission-init.md
  skills/permission-review.md

After:
  skills/permission-init/SKILL.md
  skills/permission-review/SKILL.md
```

**Why `skills/` over `commands/`:** `commands/` still works but is the legacy pattern. `skills/<name>/SKILL.md` is the current standard — consistent with superpowers, supports model-invocation (Claude can pick up skills based on context, not just explicit `/` typing), and extensible if companion files (scripts, docs) are added per skill later.

**File content:** Unchanged — only the path moves.

**Result:** After reinstalling the plugin, `/permission-init` and `/permission-review` register correctly.

---

## Change 2: Posture Default

**What:** Replace the interactive posture question (asked when no config exists) with a silent default of `balanced`.

**Behavior after the change:**

| Config state | Behavior |
|---|---|
| Project config exists (`.claude/permission-pilot.json`) | Use it, no question asked |
| Only global config exists (`~/.claude/permission-pilot.json`) | Use it, no question asked |
| Neither exists | Default to `balanced`, save to `~/.claude/permission-pilot.json`, mention in output |

**Config lookup order** (unchanged from existing skill logic):
1. `.claude/permission-pilot.json` — project-level, takes precedence
2. `~/.claude/permission-pilot.json` — global fallback

**Output message when defaulting:**
> "No posture config found — defaulting to balanced (saved to `~/.claude/permission-pilot.json`). To change globally, ask: 'set my permission-pilot posture to hardened'. To override for this project only, ask: 'set this project's posture to hardened'."

**Why `balanced`:** It is explicitly described in the skill as "reasonable middle ground" — the natural default for a user who hasn't formed an opinion yet.

**Why save globally:** The default applies everywhere until the user overrides. Per-project overrides remain available via `.claude/permission-pilot.json`.

**Why "ask Claude" not "edit the file":** More in the spirit of the tool. Claude already knows both config locations from the skill and can create the right file in the right place. The file path is documented in the README for power users.

**Applies to:** Both `permission-init` and `permission-review` skills.

---

## Out of scope

- No new `/permission-config` command — YAGNI, "ask Claude" is sufficient
- No PostInstall hook — not supported by Claude Code
- No changes to `hooks/log.sh`, `hooks/hooks.json`, or `plugin.json`
