# Unity Catalog Skill Registry — Complete Guide

> **What this is:** A governed store for AI skills (SKILL.md files + bundled references)
> inside Unity Catalog. Publish once and every engineer in the workspace loads the latest
> version on demand — no manual file copying, no stale local copies, no per-engineer installs.
>
> **Beta:** Account admins must enable this from the account console **Previews** page first.

---

## What is a UC Skill?

A Unity Catalog skill is a versioned AI instruction artifact stored in a UC schema. It
consists of a `SKILL.md` file (instructions for the coding agent) plus optional bundled
reference files, all governed by standard UC permissions.

Skills live in the three-level UC namespace: `catalog.schema.skill-name`.

The `databricks-skill-registry` MCP server (set up via `ucode`) connects your coding
agent to UC. Ask the agent to list or load a skill and it fetches the latest published
version live — nothing cached on disk unless you explicitly download it.

---

## What this solves

| Problem (without UC) | Solution (with UC) |
|---|---|
| Skills live in each engineer's `.claude/skills/` — stale and inconsistent | One source of truth in a governed UC schema |
| Updating a skill requires pushing files to every machine | Publish once — everyone gets it on next load |
| No visibility into which skills exist or who owns them | `list_skills` returns name, description, owner |
| No access control on AI instructions | UC `GRANT` / `REVOKE` — same as tables and functions |
| New engineers miss skills during onboarding | Point at the registry URL — nothing else needed |

---

## Architecture

```
Engineer's machine                     Databricks workspace
─────────────────                      ────────────────────────────
                                       Unity Catalog
Claude Code session                    └─ <catalog>
  │                                        └─ <schema>
  │  "use databricks-sql-guide"                ├─ databricks-sql-guide
  ▼                                             ├─ python-standards
databricks-skill-registry MCP ──REST──►        └─ data-patterns
  │  (runs locally, set up by ucode)
  │  fetches SKILL.md + bundled files
  ▼
Skill injected into agent context
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Unity Catalog-enabled Databricks workspace | Workspace URL required |
| Python 3.12+ and `uv` | To install `ucode` |
| `USE CATALOG`, `USE SCHEMA`, `READ VOLUME` on target schema | To load/consume skills |
| `USE SCHEMA`, `CREATE VOLUME` on target schema | To publish skills |

---

## Step 1 — Install and connect ucode

`ucode` is the official tool for both publishing and consuming UC skills. It signs you
in to your workspace and registers the `databricks-skill-registry` MCP server with your
coding agent.

```bash
uv tool install git+https://github.com/databricks/ucode
ucode configure --agents claude --workspaces https://<workspace-host>
ucode configure skills
```

Replace `<workspace-host>` with your workspace URL host
(e.g. `my-company.cloud.databricks.com`). A browser opens for you to sign in.

**Restart your agent after running these commands.**

Supported agent values for `--agents`: `claude`, `codex`, `gemini`, `opencode`, `copilot`.

> **Or let the agent do it:**
> ```
> Install ucode from its Git source and connect my coding agent to Databricks:
> 1. Run: uv tool install git+https://github.com/databricks/ucode
> 2. Run: ucode configure --agents claude --workspaces https://<workspace-host>
> 3. Run: ucode configure skills
> ```

---

## Part A — Publishing skills

### SKILL.md format

Every skill is a folder containing `SKILL.md` plus optional bundled files.

```markdown
---
name: databricks-sql-guide
description: Databricks SQL conventions for writing queries — use for any Databricks SQL authoring or review.
---

# Databricks SQL guide

- Use snake_case for table, column, and CTE names.
- Prefer named CTEs over nested subqueries.
- Always filter on partition columns when they exist.
- Never use `SELECT *`; list columns explicitly.
```

**The `description` field is the most important line.** It is what agents match against
when deciding whether to load a skill automatically. Make it specific about *what* the
skill covers and *when* to reach for it. Keep it on a single line — avoid YAML block
scalars (`>` / `>-`) to prevent formatting issues.

Folder layout with bundled references:

```
databricks-sql-guide/
├── SKILL.md                    ← required
└── references/
    ├── patterns.md             ← fetched on demand via get_skill_files
    └── examples.md
```

### Publish a skill

After `ucode` is set up, just ask the agent:

```
Publish my ./databricks-sql-guide folder to the <catalog>.<schema> schema in Databricks.
```

The agent calls the `create_skill` MCP tool on the `databricks-skill-registry` server,
which uploads the folder and registers the skill in UC. You become the owner and it
is private to you until you share it.

### Update a skill

Edit the local folder, then ask the agent:

```
Update the databricks-sql-guide skill in <catalog>.<schema> from my ./databricks-sql-guide folder.
```

The agent calls `update_skill` on the same server.

### Delete a skill

```
Delete the databricks-sql-guide skill from <catalog>.<schema>.
```

The agent calls `delete_skill`. Deletion is permanent and immediate.

### Sync an entire Git repository to a schema

If your team keeps skills in a Git repo, Databricks provides a sync notebook that
publishes the whole repo to a schema automatically (creates new, updates changed,
never deletes). Run it on a schedule to keep the schema in sync with a branch.

Get the notebook from the official docs:
[Sync a Git repo of skills to a Unity Catalog schema](https://learn.microsoft.com/en-us/azure/databricks/agents/uc-skills/create-share-uc-skills#sync-a-git-skill-repository-to-a-uc-schema)

Configure these widgets before running:

| Widget | Value |
|---|---|
| `git_url` | Your skills repo URL |
| `catalog` | Target UC catalog |
| `schema` | Target UC schema |
| `branch` | Branch to sync from |
| `git_credential_id` | Required for private repos |

---

## Part B — Sharing skills

A published skill is **private to you** until you grant access.

### Grant via Catalog Explorer (UI)

1. Open your workspace → click **Catalog**
2. Navigate to the schema → select the skill
3. Go to **Permissions** → click **Grant**
4. Enter a user email or group name
5. Select `READ VOLUME` → click **OK**

> Recipients also need `USE CATALOG` on the catalog and `USE SCHEMA` on the schema.
> Grant those on the catalog and schema the same way.

### Grant via SQL

```sql
-- Prereqs: allow access to the catalog and schema
GRANT USE CATALOG ON CATALOG <catalog> TO `account users`;
GRANT USE SCHEMA  ON SCHEMA  <catalog>.<schema> TO `account users`;

-- Grant skill access to a group
GRANT READ VOLUME ON SKILL <catalog>.<schema>.databricks-sql-guide TO `data-engineering`;

-- Grant to an individual
GRANT READ VOLUME ON SKILL <catalog>.<schema>.databricks-sql-guide TO `jane.doe@company.com`;

-- Revoke
REVOKE READ VOLUME ON SKILL <catalog>.<schema>.databricks-sql-guide FROM `data-engineering`;
```

Sharing is a grant, not a copy — recipients read the live skill under your audit.
Nothing to keep in sync.

---

## Part C — Using skills (consuming)

### Discover available skills

```
List the Databricks skills in <catalog>.<schema>.
```

The agent calls `list_skills` and returns every skill in the schema you have permission
to see.

---

### Load a skill once (current session only)

```
Use <catalog>.<schema>.databricks-sql-guide to review this query.
```

The agent calls `load_skill`, injects the instructions into context, and calls
`get_skill_files` for any bundled reference files. Nothing is saved to disk.

---

### Download a skill (every session, works offline)

Downloads to `.claude/skills/` (or `.agents/skills/`) so it loads automatically each
session without a network call.

```bash
# One skill
ucode configure skills --location <catalog>.<schema> --skill databricks-sql-guide

# Several skills
ucode configure skills --location <catalog>.<schema> --skill databricks-sql-guide,python-standards

# Entire schema
ucode configure skills --location <catalog>.<schema>
```

Restart your agent after downloading.

> A downloaded skill is a **point-in-time copy**. Re-run the download command to pick
> up a newer published version.

---

### Load a schema live (always latest)

Scopes the `databricks-skill-registry` MCP server to a whole schema. Every skill in it
appears as a live tool and any update published to UC is immediately available — no
re-download needed.

```bash
ucode configure skills --location <catalog>.<schema> --mcp
```

Restart your agent. Skills load on demand as the agent matches tasks to skill descriptions.

> Live loading works at the **schema level** only — you cannot scope it to a single skill.
> For a single skill without loading the whole schema, use load-once instead.

---

## MCP tools reference

Once `ucode` is configured, the `databricks-skill-registry` MCP server exposes these
tools to your agent:

| Tool | Who uses it | Purpose |
|---|---|---|
| `create_skill` | Skill authors | Publish a new skill from a local folder |
| `update_skill` | Skill authors | Update an existing skill from a local folder |
| `delete_skill` | Skill authors | Remove a skill from UC |
| `list_skills` | All engineers | List skills in a schema |
| `load_skill` | All engineers | Load a skill into the current session |
| `get_skill_files` | All engineers | Fetch specific bundled files from a skill |

---

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `PERMISSION_DENIED` on publish | Missing `USE SCHEMA` or `CREATE VOLUME` | Ask UC admin to grant them |
| `PERMISSION_DENIED` on load | Missing `READ VOLUME` on skill | Ask skill owner to grant `READ VOLUME` |
| Skill not visible after publish | Share step skipped | Grant `READ VOLUME` to teammates |
| Agent doesn't load skill automatically | Description too vague | Rewrite description to be specific about task and trigger |
| Downloaded skill is outdated | Point-in-time copy | Re-run `ucode configure skills --location ... --skill ...` |

---

## Quick-reference card

```
SETUP (once per machine)
  uv tool install git+https://github.com/databricks/ucode
  ucode configure --agents claude --workspaces https://<workspace-host>
  ucode configure skills
  # restart agent

PUBLISH (ask your agent)
  "Publish my ./<skill-folder> to <catalog>.<schema> in Databricks."
  → agent calls create_skill MCP tool

UPDATE (ask your agent)
  "Update the <skill-name> skill in <catalog>.<schema> from my ./<skill-folder>."
  → agent calls update_skill MCP tool

SHARE (Catalog Explorer or SQL)
  GRANT USE CATALOG ON CATALOG <catalog> TO `account users`;
  GRANT USE SCHEMA  ON SCHEMA  <catalog>.<schema> TO `account users`;
  GRANT READ VOLUME ON SKILL   <catalog>.<schema>.<skill> TO `<group>`;

LOAD ONCE    "Use <catalog>.<schema>.<skill> to help with this task."
DOWNLOAD     ucode configure skills --location <catalog>.<schema> --skill <name>
LIVE SCHEMA  ucode configure skills --location <catalog>.<schema> --mcp
DISCOVER     "List the Databricks skills in <catalog>.<schema>."
```

---

## Official references

- [Use UC Skills — Azure Databricks docs](https://learn.microsoft.com/en-us/azure/databricks/agents/uc-skills/use-uc-skills)
- [Create and share UC Skills](https://learn.microsoft.com/en-us/azure/databricks/agents/uc-skills/create-share-uc-skills)
- [ucode repository](https://github.com/databricks/ucode)
