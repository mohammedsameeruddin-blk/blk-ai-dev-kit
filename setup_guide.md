# Blackstraw AI Dev Kit — Setup Guide

> **Version 0.2.0** · Complete step-by-step guide for every platform.

---

## Before You Start

Make sure you have the following before running anything:

| Requirement | Details |
|---|---|
| **Terminal** | macOS/Linux: Terminal or iTerm2. Windows: PowerShell 5.1+ (built into Windows 10/11). |
| **Claude Code** | Install from [claude.ai/code](https://claude.ai/code). Verify with `claude --version`. |
| **Blackstraw GitHub access** | You need to be a member of the `blackstraw-ai` GitHub org to clone the repo. |
| **Databricks workspace** | You will need your workspace URL and credentials during installation. |
| **Internet connection** | Skills and tools are fetched from GitHub and Databricks during install. |

> **Do not run the official Databricks `install.sh` or `install.ps1` alongside this script.**
> The Blackstraw enterprise installer fully replaces it. Running both will overwrite the MCP configuration.

---

## Part 1 — Clone the Repository
#TODO: UPDATE THE ACTUAL REPO Details.

The kit lives at `github.com/blackstraw-ai/ai-dev-kit`. You need to be a member of the
`blackstraw-ai` GitHub organisation to access it.

### macOS / Linux

```bash
git clone https://github.com/blackstraw-ai/ai-dev-kit.git
cd ai-dev-kit
```

### Windows (PowerShell)

```powershell
git clone https://github.com/blackstraw-ai/ai-dev-kit.git
cd ai-dev-kit
```

If you don't have SSH set up or prefer HTTPS, the commands above already use HTTPS.
To use SSH instead (faster for repeated operations):

```bash
git clone git@github.com:blackstraw-ai/ai-dev-kit.git
```

> If you see a "Repository not found" error, confirm that your GitHub account has been
> added to the `blackstraw-ai` organisation. Contact your administrator for access.

---

## Part 2 — Install Dependencies

Install the following two tools before running the enterprise installer. Both are required.

---

### 1. uv — Python Package Manager

`uv` is used to create the Python virtual environment for the MCP server.

**macOS / Linux:**
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

After install, reload your shell or run:
```bash
source $HOME/.local/bin/env
```

Verify:
```bash
uv --version
```

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Restart your PowerShell session after install, then verify:
```powershell
uv --version
```

> If `uv` is not found after install, open a **new terminal window** — the PATH needs to reload.

---

### 2. Databricks CLI

The Databricks CLI is used to authenticate with your workspace and install agent skills.
Requires **v1.0.0 or higher**.

**macOS (Homebrew):**
```bash
brew install databricks
```

**Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sudo sh
```

**Windows (PowerShell):**
```powershell
winget install Databricks.DatabricksCLI
```

After install on Windows, restart your PowerShell session.

Verify (all platforms):
```bash
databricks --version
```

You should see `Databricks CLI v1.0.0` or higher.

> Full install docs: [docs.databricks.com/dev-tools/cli](https://docs.databricks.com/aws/en/dev-tools/cli/)

---

## Part 3 — Enterprise Installer

The enterprise installer sets up your project with a live Databricks MCP server, AI skills,
and Claude Code configuration. It runs in **6 steps**.

### How to run

> **Important:** Run from your **project directory** — the folder where you will use Claude
> Code. This is **not** the `ai-dev-kit` repo directory; it is your actual work project.

**macOS / Linux — from a local clone:**
```bash
cd ~/my-project
bash ~/ai-dev-kit/enterprise_install.sh
```

**macOS / Linux — one-liner, no clone needed:**
```bash
cd ~/my-project
bash <(curl -sL https://raw.githubusercontent.com/blackstraw-ai/ai-dev-kit/main/enterprise_install.sh)
```

**Windows (PowerShell) — from a local clone:**
```powershell
cd C:\Users\you\my-project
powershell -ExecutionPolicy Bypass -File C:\path\to\ai-dev-kit\enterprise_install.ps1
```

**Windows (PowerShell) — one-liner, no clone needed:**
```powershell
cd C:\Users\you\my-project
irm https://raw.githubusercontent.com/blackstraw-ai/ai-dev-kit/main/enterprise_install.ps1 | iex
```

### CLI flags

| Flag | What it does |
|---|---|
| `--skills-only` | Fast path: update skills only, skip MCP setup and auth |

---

### Step 1 of 6 — Project Directory

The installer asks which directory to set up:

```
  Project directory [/current/path]:
```

Press **Enter** to accept the current directory (recommended), or type a different path.

The installer creates `.claude/skills/` inside this directory and uses it as the root for
all configuration files.

---

### Step 2 of 6 — Prerequisites Check

The installer verifies that all required tools are present:

```
  ✓ git version 2.x.x
  ✓ uv 0.x.x
  ✓ Databricks CLI: x.x.x
```

**If the Databricks CLI is missing**, the installer attempts to install it automatically:

- macOS: tries `brew install databricks`, then falls back to the official curl installer
- Linux: falls back to the official curl installer
- Windows: runs `winget install Databricks.DatabricksCLI`

If auto-install fails, install it manually following Part 2 of this guide, open a new terminal,
and re-run the installer.

**If `git` or `uv` are missing**, the installer stops. Install them manually (Part 2), open a
new terminal, and re-run.

> **`--skills-only` mode:** Only `git` is required. The `uv` and Databricks CLI checks are
> skipped — you can re-run skills without a full uv install present.

---

### Step 3 of 6 — Databricks Workspace & Profile

*Skipped in `--skills-only` mode.*

#### Profile selection

The installer reads `~/.databrickscfg` and shows all saved profiles:

```
  Choose Databricks profile:
  ↑/↓ navigate · Enter confirm

  ❯ ● DEFAULT
    ○ staging
    ○ Create new profile...
    [ Confirm ]
```

Use the **arrow keys** to navigate and **Enter** to select. Choose **Create new profile...**
if you have not set up a profile yet or want to add a new workspace.

#### Creating a new profile

If you select **Create new profile...**, the installer prompts for:

```
  Workspace URL: https://adb-xxxx.azuredatabricks.net
  Profile name [DEFAULT]:
```

Enter your full Databricks workspace URL (find it in the address bar of your Databricks
workspace). Type a profile name or press **Enter** to use `DEFAULT`.

The installer then runs:
```bash
databricks auth login --host <workspace-url> --profile <name>
```

This opens a **browser window** where you log in with your Databricks credentials.

#### Authentication

After selecting or creating a profile, the installer checks if it is authenticated:

```
  ✓ Authenticated as firstname.lastname@company.com
```

If not authenticated, a browser window opens automatically for OAuth login. Sign in with
your Databricks credentials (typically your company SSO account), then return to the terminal.

> **How authentication works:** The Databricks CLI uses OAuth 2.0. Your credentials are
> stored securely in `~/.databrickscfg` as a token — the installer never stores passwords.
> Tokens expire and the CLI handles refresh automatically.

---

### Step 4 of 6 — Databricks MCP Server

*Skipped in `--skills-only` mode.*

This step sets up the **MCP (Model Context Protocol) server** — a Python process that
gives Claude Code live access to your Databricks workspace during a conversation.

#### What gets created

A Python virtual environment is created at `~/.ai-dev-kit/.venv` (shared across all your
projects on this machine). Two packages are installed into it:

- `databricks-tools-core` — high-level Python functions for Databricks operations
- `databricks-mcp-server` — the server that exposes these as tools to Claude Code

#### What gets written

A `.mcp.json` file is written to your project directory:

```json
{
  "mcpServers": {
    "databricks": {
      "command": "~/.ai-dev-kit/.venv/bin/python",
      "args": ["~/.ai-dev-kit/repo/databricks-mcp-server/run_server.py"],
      "defer_loading": true,
      "env": { "DATABRICKS_CONFIG_PROFILE": "DEFAULT" }
    }
  }
}
```

`defer_loading: true` means the server starts only when Claude Code first needs it —
Claude Code opens faster, and the server does not run when you are not using Databricks tools.

> **Windows:** The installer writes `Scripts/python.exe` instead of `bin/python`, using
> forward slashes and the full absolute path (e.g.
> `C:/Users/you/.ai-dev-kit/.venv/Scripts/python.exe`). You do not need to edit it manually.

> **If Claude Code is currently open** when you run the installer, the packages will update
> correctly but the new version will not take effect until you restart Claude Code.

---

### Step 5 of 6 — Skills + Settings

The most involved step. Five sub-tasks run in sequence.

#### 5a — Claude Code Settings

Writes `$PROJECT_DIR/.claude/settings.json` with a `SessionStart` hook that silently
checks for installer updates each time you open Claude Code. The check runs in the
background and only notifies you when a newer version is available.

---

#### 5b — MLflow Skills (8 skills)

Eight skill guides are downloaded from the public `github.com/mlflow/skills` repository
and saved as files in `.claude/skills/`. These teach Claude Code MLflow patterns and
best practices.

| Skill | What it covers |
|---|---|
| `agent-evaluation` | Evaluating AI agents with MLflow |
| `analyze-mlflow-chat-session` | Analysing conversation traces |
| `analyze-mlflow-trace` | Inspecting traces for debugging |
| `instrumenting-with-mlflow-tracing` | Adding tracing to your code |
| `mlflow-onboarding` | MLflow fundamentals and getting started |
| `querying-mlflow-metrics` | Retrieving and comparing experiment metrics |
| `retrieving-mlflow-traces` | Fetching and filtering traces |
| `searching-mlflow-docs` | Searching the MLflow documentation |

Each skill is a `SKILL.md` file at `.claude/skills/<skill-name>/SKILL.md`.

> If a skill download fails (e.g. due to a network issue), that skill is skipped and the
> rest continue. Re-run with `--skills-only` to retry failed skills.

---

#### 5c — Databricks Agent Skills (32 skills)

32 Databricks-specific skills are installed as a **Claude Code plugin** via
`databricks aitools install`. These come from `github.com/databricks/databricks-agent-skills`,
maintained by Databricks.

> **Note:** These skills do **not** appear as files in `.claude/skills/`. They are delivered
> through the Claude Code plugin system (`databricks@claude-plugins-official`). You will see
> them when Claude Code starts a session.

**Requires Databricks CLI v1.0.0+.** If your CLI is older, this step is skipped with an
upgrade notice.

The installer runs two commands internally:

```bash
# Register the Claude plugin marketplace
claude plugin marketplace add anthropics/claude-plugins-official

# Install the Databricks plugin
databricks aitools install --scope project --agents claude-code --experimental
```

**Stable skills (29):**

| Skill | Description |
|---|---|
| `databricks-core` | Core Databricks patterns and configuration |
| `databricks-jobs` | Workflows, scheduled jobs, multi-task DAGs |
| `databricks-pipelines` | Spark Declarative Pipelines (streaming, CDC, Auto Loader) |
| `databricks-dabs` | Databricks Asset Bundles (DABs) for deployment |
| `databricks-dbsql` | Databricks SQL queries and warehouses |
| `databricks-unity-catalog` | Unity Catalog tables, volumes, governance |
| `databricks-apps` | Databricks Apps (full-stack web applications) |
| `databricks-apps-python` | Python app frameworks (Dash, Streamlit, FastAPI, Flask) |
| `databricks-app-design` | App design patterns and UI best practices |
| `databricks-model-serving` | Deploy ML models and AI agents to endpoints |
| `databricks-vector-search` | Vector Search indexes, embeddings, semantic search |
| `databricks-ml-training` | Machine learning training workflows |
| `databricks-mlflow-evaluation` | Model evaluation with MLflow |
| `databricks-lakebase` | Lakebase (OLTP Postgres-compatible) patterns |
| `databricks-lakeflow-connect` | Lakeflow Connect for ingestion pipelines |
| `databricks-aibi-dashboards` | AI/BI dashboards and visualisations |
| `databricks-zerobus-ingest` | Zero-copy ingestion patterns |
| `databricks-metric-views` | UC metric views for business metrics |
| `databricks-agent-bricks` | Agent Bricks for building AI agents |
| `databricks-ai-functions` | AI functions in SQL |
| `databricks-data-discovery` | Data discovery and cataloguing |
| `databricks-python-sdk` | Databricks Python SDK usage |
| `databricks-docs` | Searching and referencing Databricks docs |
| `databricks-execution-compute` | Cluster and serverless compute management |
| `databricks-iceberg` | Apache Iceberg integration |
| `databricks-serverless-migration` | Migrating to serverless compute |
| `databricks-spark-structured-streaming` | Structured Streaming patterns |
| `databricks-synthetic-data-gen` | Synthetic data generation |
| `databricks-unstructured-pdf-generation` | PDF and document generation |

**Experimental skills (3):**

| Skill | Description |
|---|---|
| `databricks-ai-runtime` | AI-optimised runtime features |
| `databricks-genie` | Genie natural language query patterns |
| `spark-python-data-source` | Python Data Source API for custom connectors |

---

#### 5d — Enterprise Skills (optional)

If an enterprise skills repository is configured for your organisation (set in
`ENTERPRISE_SKILLS_REPO` in the installer), those skills are cloned and copied into
`.claude/skills/` alongside the MLflow skills.

Enterprise skills are Blackstraw-specific patterns and organisational knowledge — for
example, internal data architecture standards, naming conventions, or company-specific
workflows.

**If this step is active**, the installer:
1. Clones the private skills repo to `~/.ai-dev-kit/blackstraw-skills-repo/`
2. Copies every skill folder from the repo into your project's `.claude/skills/`
3. On re-runs, pulls the latest version of the repo

Contact your administrator to find out which enterprise skills repo is configured and
what skills are available.

---

#### 5e — Genie Sync (optional, interactive)

After skills are installed, the installer offers to upload them to your Databricks workspace
so they are also available in **Genie Code** (the AI assistant built into Databricks):

```
  Would you like to upload Skills to Genie Code? (y/n) [y]:
```

- `y` — skills are uploaded to `/Workspace/Users/<you>/.assistant/skills/` in your Databricks workspace
- `n` — skip; skills remain local to Claude Code on this machine only

Uploading uses your authenticated Databricks CLI profile from Step 3.

> To re-sync skills after an update, re-run with `--skills-only` and type `y` at this prompt.

---

### Step 6 of 6 — Workspace State Files

*Skipped in `--skills-only` mode.*

Writes state files and updates `.gitignore`. Fully automatic — no action needed.

```
  ✓ .ai-dev-kit/version
  ✓ .ai-dev-kit/.installed-skills
  ✓ .ai-dev-kit/.skills-profile
  ✓ .gitignore updated
```

The `.gitignore` is updated to exclude all kit files from source control:

```
.ai-dev-kit/
.claude/
.mcp.json
.env
__pycache__/
*.pyc
```

---

### Final Summary

When all steps complete, the installer prints a summary:

```
+========================================================+
|   ✓  Workspace Ready                                   |
+========================================================+

  Project              ~/my-project
  Enterprise           Blackstraw
  Workspace            https://adb-xxxx.azuredatabricks.net
  Profile              DEFAULT
  MLflow skills        8 installed
  Agent skills         32 installed
  Enterprise skills    [n installed, if configured]
  MCP config           ~/my-project/.mcp.json

Next steps:
  1. Open your project in Claude Code:  claude ~/my-project
  2. MCP + skills are active — try: "List my SQL warehouses"
```

---

## What Got Installed

After install, your project directory contains:

```
my-project/
├── .mcp.json                    ← MCP server configuration
├── .claude/
│   ├── settings.json            ← Claude Code session hooks
│   └── skills/                  ← MLflow + enterprise skill files
│       ├── mlflow-onboarding/
│       ├── agent-evaluation/
│       └── ...
├── .ai-dev-kit/
│   ├── version                  ← Kit version (0.2.0)
│   ├── .installed-skills        ← Log of installed skills
│   └── .skills-profile          ← Active profile (enterprise)
└── .gitignore                   ← Excludes all of the above
```

Global files (shared across all your projects):

```
~/.ai-dev-kit/
├── .venv/                       ← Python venv with the MCP server
└── repo/                        ← Shallow clone of ai-dev-kit repo (curl mode)
```

---

## Verify Your Setup

1. **Open your project in Claude Code:**
   ```bash
   claude ~/my-project
   ```

2. **Test Databricks connectivity** — try these prompts in Claude Code:
   - `"List my SQL warehouses"`
   - `"Show my Databricks clusters"`
   - `"Run SELECT 1 on my default warehouse"`

3. **Check skills are loaded** — ask Claude Code:
   - `"What Databricks skills do you have?"`
   - `"Help me create a Spark Declarative Pipeline"`

---

## Updating the Kit

### Update skills only (fastest — no MCP or auth prompts)

```bash
# macOS / Linux
bash ~/ai-dev-kit/enterprise_install.sh --skills-only

# Windows
powershell -ExecutionPolicy Bypass -File C:\path\to\enterprise_install.ps1 --skills-only
```

Use this to:
- Refresh MLflow skills after an update to `mlflow/skills`
- Re-install Databricks agent skills after a CLI upgrade
- Retry a skill that failed due to a network issue

### Full reinstall

```bash
# macOS / Linux
bash ~/ai-dev-kit/enterprise_install.sh --force

# Windows
powershell -ExecutionPolicy Bypass -File C:\path\to\enterprise_install.ps1 --force
```

### Update the kit scripts themselves

```bash
cd ~/ai-dev-kit
git pull
```

### Automatic update check

Each time you start a Claude Code session, a background hook checks whether a newer
version of the kit is available. If one is found, Claude Code displays a notification
with the update command.

---

## Resetting or Removing

### Per-project reset (removes kit config from one project)

```bash
# macOS / Linux
rm -rf .claude/ .mcp.json .ai-dev-kit/

# Windows
Remove-Item -Recurse -Force .claude, .mcp.json, .ai-dev-kit
```

Then re-run the enterprise installer from that project directory.

### Full removal (including the shared venv)

```bash
# macOS / Linux
rm -rf .claude/ .mcp.json .ai-dev-kit/ ~/.ai-dev-kit/

# Windows
Remove-Item -Recurse -Force .claude, .mcp.json, .ai-dev-kit
Remove-Item -Recurse -Force "$env:USERPROFILE\.ai-dev-kit"
```

---

## Troubleshooting

**`git` not found**
→ Install Git from [git-scm.com/downloads](https://git-scm.com/downloads) or via `brew install git` (macOS) / `sudo apt-get install git` (Linux). Then open a new terminal.

**`uv` not found after install**
→ Close your terminal completely, open a new one, then re-run. On macOS/Linux, add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile (`~/.zshrc` or `~/.bashrc`) and reload with `source ~/.zshrc`.

**`databricks: command not found`**
→ Install the CLI following Part 2 above, then open a new terminal. On Windows, restart your PowerShell session after `winget` completes.

**Windows: "cannot be loaded because running scripts is disabled"**
→ Run `Set-ExecutionPolicy Bypass -Scope Process -Force` at the top of your PowerShell session, then retry.

**Windows: parse errors or `UnexpectedToken`**
→ Make sure you are running the script file directly (`.\enterprise_install.ps1`), not copy-pasting its content. The file must be saved with UTF-8 encoding.

**"Repository not found" when cloning**
→ Your GitHub account does not have access to `blackstraw-ai/ai-dev-kit`. Contact your administrator to be added to the `blackstraw-ai` GitHub organisation.

**Databricks OAuth browser does not open**
→ Run `databricks auth login --host <your-workspace-url>` manually in a terminal. After logging in, re-run the enterprise installer.

**"Account not authenticated" after OAuth**
→ OAuth tokens can expire. Run `databricks auth login --host <workspace-url> --profile <name>` to refresh, then re-run with `--mcp-only`.

**MCP server not responding in Claude Code**
→ Verify `.mcp.json` exists in your project root. Run `claude` from the **exact** directory used during installation. If Claude Code was open during install, restart it.

**Skills not appearing in Claude Code**
→ Check `.claude/skills/` contains skill directories. Re-run with `--skills-only`:
```bash
bash ~/ai-dev-kit/enterprise_install.sh --skills-only
```

**Agent skills missing (`databricks aitools` step failed)**
→ Check your Databricks CLI version: `databricks --version`. Must be v1.0.0 or higher. Upgrade with `brew upgrade databricks` (macOS) or the official installer, then re-run with `--skills-only`.

**GitHub rate limit during skills install (HTTP 429)**
→ GitHub throttles unauthenticated requests to `raw.githubusercontent.com`. Wait ~60 seconds, then re-run with `--skills-only`.

**"Could not sync skills to Genie"**
→ Ensure your Databricks CLI is v0.200+. You can also upload manually:
```bash
databricks workspace import-dir .claude/skills /Workspace/Users/<your-email>/.assistant/skills \
  --overwrite --profile DEFAULT
```

**Skills stale after an update**
→ Re-run with `--skills-only`. If Genie sync was previously set up, answer `y` at the sync prompt to re-upload.

---

## Version

This guide applies to **Blackstraw Enterprise AI Dev Kit v0.2.0**.

Check your installed version at any time:

```bash
cat .ai-dev-kit/version
```
