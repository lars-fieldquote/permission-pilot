# permission-pilot

A Claude Code plugin that passively logs tool usage and helps you generate a calibrated allow-list — so you stop getting interrupted by safe commands without losing visibility on risky ones.

## The problem

Claude Code's permission system has no middle ground: default mode prompts constantly, bypass mode leaves you blind. This plugin learns from your actual workflow and helps you craft a minimal, targeted allow-list.

## What it does

- **Passive logging** — every permission request and bash command is logged to `~/.claude/permission-log.jsonl`. Zero friction, fully async.
- **`/permission-init`** — reads your project files, asks about your security posture (loose / balanced / hardened), and generates a starter allow-list on day 1.
- **`/permission-review`** — analyzes your logs against your current settings and posture. Shows you where you're being blocked unnecessarily and where you're over-permissive.

## Install

```bash
/plugin marketplace add lars-fieldquote/permission-pilot
/plugin install permission-pilot
```

## Usage

**Day 1 — generate a starter allow-list:**
```
/permission-init
```

**After a few days of use — tune your settings:**
```
/permission-review
/permission-review --days 7
/permission-review --all-projects
```

## Security posture

Both commands respect your posture setting:

| Posture | Best for | Behavior |
|---|---|---|
| `loose` | Personal projects, solo dev | Allow most things, prompt only for truly dangerous ops |
| `balanced` | Most users (default) | Allow safe patterns, prompt for deploy/delete/network |
| `hardened` | Production systems, sensitive repos | Tight control, prompt for anything non-trivial |

Set globally: `~/.claude/permission-pilot.json`
Override per project: `.claude/permission-pilot.json`

```json
{ "posture": "balanced", "log_retention_days": 30 }
```

## Log file

`~/.claude/permission-log.jsonl` — one JSON object per line:

```json
{"ts":"2026-04-06T10:23:00Z","trigger":"permission","session_id":"abc","project":"/home/user/myapp","tool":"Bash","input":"npm install","reviewed":false}
```

Entries older than `log_retention_days` are pruned automatically when you run `/permission-review`. Nothing is deleted silently in the background.

## Note on bypass mode

`PermissionRequest` does not fire when Claude Code is in bypass/dangerous mode. In that case, the `PreToolUse(Bash)` hook provides coverage — all bash commands are still logged, but the `trigger` field will be `tool_use` rather than `permission`.

## Prior art & inspiration

- [dylancaponi/claude-code-permissions](https://github.com/dylancaponi/claude-code-permissions) — curated deny-list with pre-hook validation. Great static baseline.
- [SpillwaveSolutions/claude_permissions_skill](https://github.com/SpillwaveSolutions/claude_permissions_skill) — pioneered natural language → permission config. Inspired `/permission-init`.

permission-pilot adds persistent logging, posture-aware recommendations, and closed-loop review on top of their ideas.

## License

MIT
