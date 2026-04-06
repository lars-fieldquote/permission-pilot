# permission-pilot Design Spec

**A Claude Code plugin that passively logs tool usage, then helps you generate and tune a calibrated allow-list based on your actual workflow and desired security posture.**

---

## Problem

Claude Code's permission system offers no middle ground: default mode interrupts constantly, bypass mode leaves you blind. There is no tool that learns from your actual usage patterns and helps you craft a minimal, targeted allow-list that silences safe operations while keeping guards on risky ones.

Existing tools:
- **dylancaponi/claude-code-permissions** — static curated deny-list, no learning
- **SpillwaveSolutions/claude_permissions_skill** — natural language → one-shot config, no logging or analysis

Neither closes the loop between "what Claude actually does" and "what your settings allow."

---

## Solution

Three components forming a closed loop:

```
[log hook] ──────────────────→ ~/.claude/permission-log.jsonl
                                            ↓
                               [/permission-review skill]
                                     ↙           ↘
                              friction         over-permissive
                                     ↘           ↙
                               updated settings.json

[/permission-init skill] ← reads project files + posture → settings.json
```

---

## Security Posture

Both skills are posture-aware. Posture is set once and stored — not asked on every run.

**Three levels:**
- `loose` — solo dev, personal projects, minimize interruptions
- `balanced` — reasonable middle ground (default)
- `hardened` — production systems, sensitive data, tight control

**Config hierarchy** (first found wins):
1. `.claude/permission-pilot.json` in current project — project override
2. `~/.claude/permission-pilot.json` — user default
3. Neither exists → skill asks once, saves to `~/.claude/permission-pilot.json`

**Config format:**
```json
{ "posture": "balanced", "log_retention_days": 30 }
```

Project override only needs to specify what differs:
```json
{ "posture": "hardened" }
```

---

## Component 1: Log Hook

### What it captures

Two hook events, both async (never block Claude):

| Hook | Filter | Trigger tag | Captures |
|---|---|---|---|
| `PermissionRequest` | none | `permission` | Everything Claude had to ask about in default mode |
| `PreToolUse` | `Bash` | `tool_use` | All bash commands, including bypass mode |

> **Assumption to verify early:** `PermissionRequest` likely does not fire in bypass mode. If confirmed, `PreToolUse(Bash)` is the sole capture path for bypass sessions. Document this clearly in README.

### Log format

One JSON object per line in `~/.claude/permission-log.jsonl`:

```json
{
  "ts": "2026-04-06T10:23:00Z",
  "trigger": "permission",
  "session_id": "abc123",
  "project": "/home/user/myapp",
  "tool": "Bash",
  "input": "npm install",
  "reviewed": false
}
```

Fields:
- `ts` — ISO 8601 timestamp
- `trigger` — `"permission"` or `"tool_use"`
- `session_id` — from hook env var (exact var name to verify during implementation)
- `project` — from `$PWD`
- `tool` — tool name from hook context
- `input` — full tool input (bash command, file path, etc.)
- `reviewed` — set to `true` after `/permission-review` acts on this entry

### Log lifecycle

- **Active window:** 30 days by default (configurable via `log_retention_days`)
- **Pruning:** only during `/permission-review` runs — never silently in background, never during `/permission-init`
- **Mark-reviewed:** entries acted upon during a review get `reviewed: true` and stop surfacing in future reviews until new instances appear

---

## Component 2: `/permission-init` skill

Day-1 value: generates a smart allow-list without needing log data.

### Flow

1. Check posture config (hierarchy above); ask and save if missing
2. Read project files to understand the stack:
   - `package.json`, `yarn.lock`, `pnpm-lock.yaml` — Node/JS
   - `Cargo.toml` — Rust
   - `requirements.txt`, `pyproject.toml`, `Pipfile` — Python
   - `docker-compose.yml`, `Dockerfile` — containers
   - `Makefile` — custom task runner
   - `.env.example` — hints at external services
   - `*.tf` — Terraform
3. Reason about safe/contextual/sensitive commands for this stack + posture
4. For contextual ambiguities, run a short interview:
   - "Is this a personal dev machine or a shared/production environment?"
   - "Do you deploy from this machine directly?"
5. Output a ready-to-paste `permissions.allow` block with brief rationale per entry

### Output example

```json
// Recommended additions to ~/.claude/settings.json → permissions.allow
// Posture: balanced | Stack: Node.js + Docker
[
  "Bash(npm install*)",       // safe: dependency installation
  "Bash(npm run*)",           // safe: project scripts
  "Bash(docker-compose up*)", // contextual: local dev only
  "Bash(git status*)",        // safe: read-only git
  "Bash(git diff*)"           // safe: read-only git
]
// Kept at prompt: rm -rf, git push --force, curl (external), docker push
```

---

## Component 3: `/permission-review` skill

Closes the loop: analyzes logs against current settings and posture.

### Flow

1. Load logs — filter to current project + last 30 days (or `--all-projects`, `--days N`)
2. Check posture config
3. Load current `~/.claude/settings.json` permissions block
4. Cross-reference and identify:
   - **Friction**: commands that were blocked/prompted repeatedly that look safe for your posture
   - **Over-permissive**: patterns allowed but never triggered, or risky for your posture
5. For ambiguous patterns, run a short interview:
   - "You run `./deploy.sh` regularly — does this ever touch production?"
6. Output two sections + ready-to-paste settings block
7. Ask: "Apply these recommendations?" — if yes, mark relevant log entries as `reviewed: true`

### Output example

```
Friction (consider allowing):
  npm test          — ran 47x, blocked 12x, safe for 'balanced'
  docker-compose up — ran 23x, blocked 8x, safe for 'balanced' on local dev

Over-permissive (consider tightening):
  Bash(curl*)       — allowed but never triggered in 30 days
  Bash(rm*)         — risky for 'balanced', consider Bash(rm ./tmp/*)

Ready-to-paste block: [...]
```

---

## Repo Structure

```
permission-pilot/
├── .claude-plugin/
│   ├── plugin.json          # name, version, author, homepage
│   └── marketplace.json     # self-hosted marketplace entry
├── hooks/
│   └── log.sh               # PermissionRequest + PreToolUse logger
├── skills/
│   ├── permission-init.md   # stack-aware init skill
│   └── permission-review.md # log analysis + tuning skill
└── README.md
```

---

## README: Prior Art & Inspiration

The README will include a "Prior art" section crediting:
- [dylancaponi/claude-code-permissions](https://github.com/dylancaponi/claude-code-permissions) — curated deny-list with pre-hook validation
- [SpillwaveSolutions/claude_permissions_skill](https://github.com/SpillwaveSolutions/claude_permissions_skill) — pioneered natural language → permission config

permission-pilot builds on their ideas with logging, posture-awareness, and closed-loop review.

---

## Out of Scope (v1)

- Real-time filtering or blocking (not a security boundary tool)
- MCP tool logging (bash-only for now)
- Team/shared settings sync
- GUI or web dashboard
