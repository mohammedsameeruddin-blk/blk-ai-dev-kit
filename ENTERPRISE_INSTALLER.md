# Blackstraw Enterprise AI Dev Kit — Installer Reference

> **Two scripts, same behaviour:**
> `enterprise_install.sh` (macOS / Linux) and `enterprise_install.ps1` (Windows) run the
> same 6-step workflow. Differences are implementation-level only (bash vs PowerShell).

---

## What it does

Sets up a Claude Code project with:

1. A live **Databricks MCP server** — so Claude Code can query your workspace during a conversation
2. **MLflow skills** — 8 prompting guides downloaded from `github.com/mlflow/skills`
3. **Databricks agent skills** — 32 skill definitions installed as a Claude Code plugin via `databricks aitools`
4. **Enterprise private skills** — optional, from your own private Git repo
5. Project config files (`.mcp.json`, `.claude/settings.json`, `.gitignore`)

> **Important:** Do NOT run the official Databricks `install.sh` alongside this script.
> This enterprise installer fully replaces it. Running both will break the MCP config.

---

## How to run

### macOS / Linux

```bash
# From a local clone of this repo
bash enterprise_install.sh

# One-liner — no clone needed
bash <(curl -sL https://raw.githubusercontent.com/blackstraw-ai/ai-dev-kit/main/enterprise_install.sh)

# With a specific Databricks profile
bash enterprise_install.sh --profile my-workspace

# Update skills only (fast path — no MCP setup, no auth prompts)
bash enterprise_install.sh --skills-only
```

### Windows (PowerShell)

```powershell
# From a local clone
.\enterprise_install.ps1

# One-liner from GitHub
irm https://raw.githubusercontent.com/blackstraw-ai/ai-dev-kit/main/enterprise_install.ps1 | iex

# Update skills only
$env:DEVKIT_SKILLS_ONLY='true'
irm https://raw.githubusercontent.com/blackstraw-ai/ai-dev-kit/main/enterprise_install.ps1 | iex
```

---

## CLI flags

| Flag | Short | What it does |
|------|-------|--------------|
| `--profile NAME` | `-p` | Use this Databricks config profile instead of prompting |
| `--skills-only` | | Fast path: runs Steps 2 + 5 only. Uses current directory. Skips MCP, auth, state files. |
| `--mcp-only` | | Runs everything except the skills install loop in Step 5 |
| `--global` | `-g` | Install with `--scope global` instead of `--scope project` |
| `--force` | `-f` | Force reinstall even if already installed |
| `--silent` | | Suppress all output except fatal errors |

## Environment variable overrides

| Variable | Default | Effect |
|----------|---------|--------|
| `DEVKIT_PROFILE` | `DEFAULT` | Databricks config profile (same as `--profile`) |
| `DEVKIT_FORCE` | `false` | Force reinstall |
| `DEVKIT_SKILLS_ONLY` | `false` | Skills-only mode (PowerShell — bash uses the flag instead) |
| `AIDEVKIT_HOME` | `~/.ai-dev-kit` | Override the base install directory |

---

## Pre-flight: Repo detection

Before Step 1, the installer figures out where the kit code lives.

**Local clone:** If the script's own directory contains both `databricks-mcp-server/` and
`databricks-tools-core/`, it uses that directory as the repo root. No network call.

**Piped via curl:** Clones `ENTERPRISE_KIT_REPO` (shallow, `--depth 1`) to
`~/.ai-dev-kit/repo/`. On re-runs it does `git fetch && git reset --hard FETCH_HEAD` to
stay current. A failed update falls back to the cached version with a warning rather
than aborting.

---

## Step 1 — Project Directory

*Skipped in `--skills-only` mode (uses `pwd`).*

Prompts for the project directory, defaulting to the current working directory.
Three sanitisation steps run after the user confirms:

1. **Strip trailing slashes/backslashes** — Arrow-key navigation in the profile selector
   can leave a stray `\` in the tty buffer. Without stripping it, `PROJECT_DIR` becomes
   a corrupt path like `/your/path/\`, which breaks every subsequent path operation.

2. **Empty check** — If the stripped result is empty, fall back to `pwd`.

3. **Canonicalise** — `mkdir -p` then `cd && pwd` resolves symlinks and confirms the
   directory exists.

```bash
PROJECT_DIR=$(prompt "Project directory" "$(pwd)")
PROJECT_DIR="$(echo "$PROJECT_DIR" | sed 's|[/\\]*$||')"   # strip tty noise
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$(pwd)"
mkdir -p "$PROJECT_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
```

After this, `$PROJECT_DIR/.claude/skills/` is created.

---

## Step 2 — Prerequisites

Checks for required tools. Behaviour when a tool is missing:

| Tool | Required for | If missing |
|------|-------------|------------|
| `git` | All modes | **Fatal** — prints instructions to run `prerequisites.sh` |
| `uv` | Full install | **Fatal** — same |
| Databricks CLI | Full install | Auto-installs, then **warns** if that also fails |

*`uv` and the Databricks CLI check are skipped in `--skills-only` mode.*

### Databricks CLI auto-install

**macOS/Linux:** Tries `brew install databricks` first; falls back to the official
curl installer at `https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh`.

**Windows:** Tries `winget install Databricks.DatabricksCLI`, then `choco install
databricks-cli`. Refreshes `$env:Path` after install so the binary is immediately
visible in the current session.

If auto-install fails, a warning is printed with a manual install link and the
installer continues (the Databricks CLI is tested again later when it's actually
needed).

---

## Step 3 — Databricks Workspace & Profile

*Skipped in `--skills-only` mode.*

### Profile selection

The installer reads `~/.databrickscfg` and collects all `[section]` headers (profile
names). If profiles exist and `--profile` was not passed on the command line, an
**arrow-key radio selector** is shown:

```
  Choose Databricks profile:
  ↑/↓ navigate · Enter confirm

  ❯ ● DEFAULT               default
    ○ staging
    ○ Create new profile...  enter workspace URL and profile name
    [ Confirm ]
```

In non-TTY environments (CI, piped execution), a numbered fallback list is shown
and `read` / `Read-Host` is used.

### Creating a new profile

Prompts for workspace URL (e.g. `https://adb-xxxx.azuredatabricks.net`) and a
profile name, then runs:

```bash
databricks auth login --host "$WORKSPACE_URL" --profile "$PROFILE"
```

This opens a browser window for OAuth authentication.

### Using an existing profile

Parses the `host =` line from the selected profile's section in `.databrickscfg`
to derive the workspace URL. Then calls `databricks current-user me --output json`
to check authentication:

- **Email returned** → already authenticated, confirmed
- **No email** → opens browser OAuth login via `databricks auth login`

---

## Step 4 — Databricks MCP Server

*Skipped in `--skills-only` mode.*

Sets up the Python server that gives Claude Code live access to your Databricks
workspace during a conversation.

### Python virtual environment

Creates `~/.ai-dev-kit/.venv` targeting Python 3.11:

```bash
uv venv --python 3.11 --allow-existing "$VENV_DIR"
```

Falls back to whatever Python `uv` finds if 3.11 is unavailable.

### Package installation

Installs two editable packages from the kit repo into the venv:

```bash
uv pip install --python "$VENV_PYTHON" --native-tls \
    -e "$REPO_DIR/databricks-tools-core" \
    -e "$REPO_DIR/databricks-mcp-server" --quiet
```

Verifies with `python -c "import databricks_mcp_server"`. **Dies** if this fails.

On Windows, the installer detects whether an existing MCP server process is running
(i.e. Claude Code is open) and warns that the new version only takes effect after
restarting Claude Code.

### Writing .mcp.json

An inline Python script safely **merges** the Databricks entry into
`$PROJECT_DIR/.mcp.json`, preserving any other MCP servers already configured:

```json
{
  "mcpServers": {
    "databricks": {
      "command": "~/.ai-dev-kit/.venv/bin/python",
      "args":    ["~/.ai-dev-kit/repo/databricks-mcp-server/run_server.py"],
      "defer_loading": true,
      "env":     { "DATABRICKS_CONFIG_PROFILE": "DEFAULT" }
    }
  }
}
```

`defer_loading: true` means the MCP server only starts when Claude Code first
needs it, not on every session open.

---

## Step 5 — Skills + Settings

The most involved step. Four sub-tasks run in sequence.

### 5a — Claude Code settings

Writes or merges `$PROJECT_DIR/.claude/settings.json`. The only addition is a
`SessionStart` hook that auto-checks for installer updates each time a Claude Code
session starts:

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.ai-dev-kit/repo/.claude-plugin/check_update.sh",
        "timeout": 5
      }]
    }]
  }
}
```

Idempotent — the hook is only added if `check_update` is not already present in the
file.

---

### 5b — MLflow skills

Downloads 8 prompting guides from the public `mlflow/skills` GitHub repo and places
each under `$PROJECT_DIR/.claude/skills/<skill-name>/SKILL.md`.

| Skill name |
|------------|
| `agent-evaluation` |
| `analyze-mlflow-chat-session` |
| `analyze-mlflow-trace` |
| `instrumenting-with-mlflow-tracing` |
| `mlflow-onboarding` |
| `querying-mlflow-metrics` |
| `retrieving-mlflow-traces` |
| `searching-mlflow-docs` |

For each skill, optional supplementary files are also fetched if they exist:
`reference.md`, `examples.md`, `api.md`.

**Resilience:** `curl --retry 2 --retry-delay 1` (bash) or `Invoke-WebRequest` with
try/catch (PowerShell). A 500ms sleep between each skill prevents network burst.
If a skill fails, its directory is removed and a warning is printed — the remaining
skills still install.

Each successfully installed skill is logged to
`$PROJECT_DIR/.ai-dev-kit/.installed-skills`.

> **GitHub rate limiting (HTTP 429)**
> GitHub throttles unauthenticated requests to `raw.githubusercontent.com`. A normal
> single install will not trigger this. Repeated installs during testing from the same
> IP can. If it happens, wait ~60 seconds and re-run with `--skills-only`.

---

### 5c — Databricks agent skills

Installs 32 Databricks-specific skill definitions as a **Claude Code plugin**
(not as files on disk). Requires Databricks CLI v1.0.0+.

Three sub-steps run in order:

**1. Register the Claude plugin marketplace**

```bash
claude plugin marketplace add anthropics/claude-plugins-official
```

This must run *before* `databricks aitools install`. Without it, `aitools install`
exits 0 but silently installs nothing. If the marketplace is already registered,
`claude plugin marketplace update` is run instead to pull the latest.

**2. Install the plugin**

```bash
databricks aitools install \
    --scope project \
    --agents claude-code \
    --experimental \
    -p "$PROFILE"
```

This installs `databricks@claude-plugins-official` into the Claude Code project scope,
delivering 29 stable + 3 experimental agent skill definitions.

**3. Verify the plugin registered**

Checks `claude plugin list --json` (falls back to plain `claude plugin list`) for
`databricks@claude-plugins-official`. If not found, prints a manual recovery command
rather than failing the install.

**Count reporting:** The reported count (32) comes from a hardcoded name list that
mirrors the official installer's own approach — no additional API call is made. This
avoids a second GitHub round-trip that could also rate-limit.

> Agent skills are delivered via the plugin system and appear in Claude Code's context
> window. They do **not** create files in `.claude/skills/`.

If the Databricks CLI is below v1.0.0 or missing, the step is skipped with a warning
and upgrade instructions.

---

### 5d — Enterprise private skills (optional)

Controlled by `ENTERPRISE_SKILLS_REPO` at the top of the installer file. Empty by
default — the step is skipped entirely if not configured.

When configured:

1. **SSH test** — runs `ssh -T git@github.com`. Falls back to HTTPS if SSH is not
   available, by rewriting `git@github.com:org/repo.git` → `https://github.com/org/repo.git`.
2. **Reachability check** — `git ls-remote` before attempting clone.
3. **Clone or update** — shallow clone to `~/.ai-dev-kit/<ENTERPRISE_NAME>-skills-repo/`.
   On re-runs: `git fetch --depth 1 && git reset --hard FETCH_HEAD`. If the remote URL
   changed, the local clone is deleted and re-cloned fresh.
4. **Copy skills** — every subdirectory in the repo (or in `ENTERPRISE_SKILLS_REPO_SUBPATH`
   if set) is copied to `$PROJECT_DIR/.claude/skills/`. Directories named `TEMPLATE`
   are skipped.

---

### 5e — Genie sync (optional, interactive)

After skills are installed, if the Databricks CLI returns an authenticated user email,
the installer prompts:

```
Would you like to upload Skills to Genie Code? (y/n) [y]:
```

If confirmed, every skill folder is uploaded to the authenticated user's Databricks
workspace:

```
/Workspace/Users/<your-email>/.assistant/skills/
```

Uses `databricks workspace mkdirs` to create the path, then
`databricks workspace import-dir --overwrite` for each skill folder. Reports how many
skills failed to sync.

---

## Step 6 — Workspace State Files

*Skipped in `--skills-only` mode.*

Writes three small state files to `$PROJECT_DIR/.ai-dev-kit/`:

| File | Content |
|------|---------|
| `version` | Version string from `$REPO_DIR/VERSION`, or `"enterprise"` if no VERSION file |
| `.installed-skills` | One line per file-based skill: `$SKILLS_DEST\|skill-name` |
| `.skills-profile` | Literal string `enterprise` |

### .gitignore

Appends the following rules (idempotent — checks before appending):

```
.ai-dev-kit/
.claude/
.mcp.json
.env
__pycache__/
*.pyc
```

This prevents local install state, credentials, and Claude Code config from being
committed to the project repository.

---

## Fast paths

### `--skills-only`

Runs Steps 2 and 5 only. Uses current directory as project dir. Skips: workspace
auth, MCP server setup, state files.

Use this to refresh skills after:
- A GitHub rate-limit wait (MLflow skills failed with 429)
- The enterprise skills repo was updated
- Agent skills failed due to a CLI version issue

### `--mcp-only`

Runs all steps except the skills install loop inside Step 5. Use after a Python
dependency update or when re-pointing the MCP server at a different Databricks profile.

---

## Files created

| Path | Purpose |
|------|---------|
| `$PROJECT_DIR/.mcp.json` | Tells Claude Code how to start the Databricks MCP server |
| `$PROJECT_DIR/.claude/settings.json` | Claude Code project settings (SessionStart hook) |
| `$PROJECT_DIR/.claude/skills/<name>/SKILL.md` | MLflow and enterprise skill files |
| `$PROJECT_DIR/.ai-dev-kit/version` | Installed version string |
| `$PROJECT_DIR/.ai-dev-kit/.installed-skills` | Log of installed file-based skills |
| `$PROJECT_DIR/.ai-dev-kit/.skills-profile` | Always `enterprise` |
| `$PROJECT_DIR/.gitignore` | Updated with exclusion rules |
| `~/.ai-dev-kit/.venv/` | Python venv containing the MCP server |
| `~/.ai-dev-kit/repo/` | Shallow clone of this enterprise kit repo (curl mode only) |
| `~/.ai-dev-kit/<NAME>-skills-repo/` | Shallow clone of the enterprise skills repo |

---

## Enterprise configuration block

The top section of both installer files (between the `ENTERPRISE CONFIGURATION`
comments) is the only part you need to edit when deploying to a new organisation.

| Variable | Default | Purpose |
|----------|---------|---------|
| `ENTERPRISE_NAME` | `Blackstraw` | Used in path names and banner text |
| `ENTERPRISE_DISPLAY` | `Blackstraw` | Human-readable name in the terminal banner |
| `ENTERPRISE_KIT_REPO` | GitHub URL | This installer's repo — used for self-clone/update |
| `ENTERPRISE_KIT_BRANCH` | `main` | Branch to clone from |
| `MIN_AITOOLS_CLI_VERSION` | `1.0.0` | Minimum CLI version for agent skills |
| `MLFLOW_SKILLS` | 8 names | Space-separated list of MLflow skill names to download |
| `AGENT_B_STABLE_FALLBACK` | 29 names | Known stable agent skill names (for count reporting) |
| `AGENT_B_EXPERIMENTAL_FALLBACK` | 3 names | Experimental agent skills |
| `ENTERPRISE_SKILLS_REPO` | `""` | Clone URL of your private skills repo (empty = skip) |
| `ENTERPRISE_SKILLS_REPO_SUBPATH` | `""` | Subfolder inside the repo containing skill directories |

---

## Final summary output

After all steps complete, the installer prints a summary. Normal mode:

```
+========================================================+
|   ✓  Workspace Ready                                   |
+========================================================+

  Project              /your/project/path
  Enterprise           Blackstraw
  Workspace            https://adb-xxxx.azuredatabricks.net
  Profile              DEFAULT
  MLflow skills        8 installed
  Agent skills         32 installed via databricks aitools
  Enterprise skills    14 installed
  MCP config           /your/project/.mcp.json

Next steps:
  1. Open your project in Claude Code:  claude /your/project/path
  2. MCP + skills are active — try: "List my SQL warehouses"
```

In `--skills-only` mode the box shows `✓ Skills Updated` and only the skill counts
(no workspace, profile, or MCP config line).

---

## Windows parity notes

`enterprise_install.ps1` is a faithful translation. The step logic and output are
identical. Key implementation differences:

| Bash | PowerShell |
|------|-----------|
| `curl -fsSL` | `Invoke-WebRequest -UseBasicParsing` |
| `radio_select()` | `Select-Radio` using `$host.UI.RawUI.ReadKey` |
| `prompt()` | `Read-Prompt` using `Read-Host` |
| `brew install databricks` | `winget` → `choco` fallback |
| `set -e` | `$ErrorActionPreference + $LASTEXITCODE` checks per call |
| Python heredoc `<<PYEOF` | Inline string `$script = @"..."@; & python -c $script` |
| `VENV_DIR/bin/python` | `VENV_DIR\Scripts\python.exe` |

The settings.json Python script on Windows tries `$VENV_PYTHON` first, then falls
back to system `python` and `python3` in case the venv is not yet available.
