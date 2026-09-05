---
name: blk-skills-sync
description: >-
  Manage Blackstraw enterprise skills from Unity Catalog — sync, update, list,
  and configure the live MCP connection to the skill registry.
  Use when an engineer wants to get the latest skills, check what skills are
  available, set up or refresh the live registry connection, or troubleshoot
  skill loading. Triggers on "sync skills", "update skills", "get latest skills",
  "skills registry", "what skills are available", "install enterprise skills",
  "refresh skills", "blk-skills-sync".
  Do NOT use for publishing or creating new skills — that is handled via the
  GitHub workflow or Databricks notebook job.
allowed-tools: Bash, Read
---

# Blackstraw Skills Sync

Manages the connection between an engineer's local Claude Code environment and
the Blackstraw enterprise skill registry in Unity Catalog (`blackstraw.ai_skills`).

## Purpose

Engineers should never need to remember `ucode` commands. This skill handles
all skill registry operations — checking status, syncing updates, and configuring
the live MCP connection — through a simple conversational interface.

## When to Use

**Use this skill when an engineer asks:**
- "What Blackstraw skills are available?"
- "Sync / update my skills"
- "I want the latest enterprise skills"
- "Set up live skills from UC"
- "Check if my skills are up to date"
- "Something is wrong with my skills / a skill isn't loading"

**Do NOT use for:**
- Publishing new skills to UC (use the GitHub workflow or Databricks notebook)
- Creating or editing skill content (use `SKILL_TEMPLATE` and open a PR)

---

## Hard Rules

- **NEVER** run `ucode publish` or any write operation — this skill is read/sync only
- **ALWAYS** check if `ucode` is installed before running any ucode command
- **ALWAYS** show the engineer what changed after a sync
- If `ucode` is not installed, run the install step first before continuing

---

## Workflow

### Step 1: Check ucode is installed

```bash
which ucode || echo "NOT_INSTALLED"
ucode --version 2>/dev/null || echo "NOT_INSTALLED"
```

**If not installed:**
```bash
uv tool install git+https://github.com/databricks/ucode --quiet
```

Confirm install succeeded before proceeding.

**Checkpoint:** `ucode --version` returns a version string.

---

### Step 2: Determine what the engineer wants

Ask or infer from context:

| Intent | Action |
|---|---|
| "What skills exist?" / "List skills" | Run list → show table |
| "Sync" / "Update" / "Get latest" | Run download sync |
| "Connect live" / "Set up MCP" | Run MCP configure |
| "Status" / "What do I have?" | Compare local vs UC |
| "Something broken" | Run status check, diagnose |

---

### Step 3a: List available skills

```bash
ucode skills list --location blackstraw.ai_skills
```

Show the engineer a clean table of what is in the registry: skill name, version,
last updated. Highlight any skills they do not have locally.

---

### Step 3b: Sync (download mode — offline-safe)

Downloads the latest versions of all skills to `.claude/skills/`:

```bash
ucode configure skills --location blackstraw.ai_skills
```

After sync, show:
- Which skills were added (new)
- Which skills were updated (version changed)
- Which skills were unchanged
- Full list of skills now available locally

---

### Step 3c: Connect live (MCP mode — recommended)

Sets up the always-latest live connection. No manual syncing ever needed again:

```bash
ucode configure skills --location blackstraw.ai_skills --mcp
```

After connecting:
- Tell the engineer to restart Claude Code to activate the MCP connection
- Confirm the registry URL: `blackstraw.ai_skills`
- Explain: skills load live from UC on every session, updates are automatic

---

### Step 3d: Status check

Compare what the engineer has locally vs what is in UC:

```bash
# What's in UC
ucode skills list --location blackstraw.ai_skills

# What's installed locally
ls ~/.claude/skills/ 2>/dev/null || ls .claude/skills/ 2>/dev/null || echo "No local skills found"
```

Report:
- Skills in UC but not local → suggest sync
- Skills local but not in UC → may be stale, flag for review
- Workspace connection status → reachable / unreachable

---

### Step 4: Confirm and summarise

After any operation, confirm to the engineer:
1. What was done
2. Which skills are now active
3. Whether a Claude Code restart is needed (only for MCP mode changes)
4. How to get future updates (one-liner reminder)

---

## Quick Reference (show this when engineer asks "how do I...")

| Task | What this skill does |
|---|---|
| See all available skills | "List skills from blackstraw.ai_skills" |
| Get latest versions locally | "Sync skills" |
| Stay always up-to-date | "Connect skills live" |
| Check what I have | "Skills status" |
| Fix a broken skill | "Check skills status" → diagnose |

---

## Workspace Config

- **Registry location:** `blackstraw.ai_skills`
- **Workspace:** configured via `ucode configure --agents claude --workspaces <url>`
- **UC grants required:** `USE CATALOG` + `USE SCHEMA` + `READ VOLUME` on `blackstraw.ai_skills`
