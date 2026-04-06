# permission-pilot — Project Instructions

## Version bump required before every push

**Always bump the version in `.claude-plugin/plugin.json` before pushing to any branch that will be merged to `main`.**

The Claude Code plugin system caches plugins by version. Without a version bump, reinstalling the plugin reuses the old cached files — users won't get the updated skills, hooks, or agents.

Use semantic versioning:
- `patch` (0.1.0 → 0.1.1): skill text changes, bug fixes, hook tweaks
- `minor` (0.1.0 → 0.2.0): new skills, agents, or hooks added
- `major` (0.1.0 → 1.0.0): breaking changes to skill interface or hook behavior

## Plugin structure

Skills must use the subdirectory pattern — flat `.md` files are not picked up:
```
skills/<name>/SKILL.md   ✓
skills/<name>.md          ✗
```
