#!/usr/bin/env bash
#
# Blackstraw Enterprise AI Dev Kit — Installer v2 (macOS / Linux)
#
# 6-step setup: project dir, prerequisites, workspace/profile, MCP server,
# skills (all upstream profiles + UC Skill Registry), Claude settings + Genie sync,
# state files.
#
# v2 change: enterprise private skills are now served from Unity Catalog via
# the databricks-skill-registry MCP server (ucode). No private Git repo clone.
#
# Usage:
#   bash enterprise_install_v2.sh
#   bash enterprise_install_v2.sh --profile NAME
#   bash enterprise_install_v2.sh --skills-only   # update skills only (Steps 2 + 5)
#   bash enterprise_install_v2.sh --force
#   bash enterprise_install_v2.sh --global        # install globally (not per-project)
#   bash <(curl -sL https://raw.githubusercontent.com/blackstraw-ai/ai-dev-kit/main/enterprise_install_v2.sh)
#
# Options:
#   -p, --profile NAME     Databricks profile (default: DEFAULT)
#   -g, --global           Install globally (not per-project)
#   --skills-only          Fast path: only update skills (Steps 2 + 5 only)
#   --mcp-only             Skip skills installation
#   --silent               No output except errors
#   -f, --force            Force reinstall
#
# Environment overrides:
#   DEVKIT_PROFILE=NAME    Databricks config profile
#   DEVKIT_FORCE=true      Force reinstall
#   DEVKIT_SKILLS_ONLY=true  Skills-only mode
#   AIDEVKIT_HOME=PATH     Install dir (default: ~/.ai-dev-kit)
#

set -e

# =============================================================================
# ── ENTERPRISE CONFIGURATION  (edit this section for your organisation) ──────
# =============================================================================

ENTERPRISE_NAME="Blackstraw"
ENTERPRISE_DISPLAY="Blackstraw"

# GitHub URL for this enterprise installer repo — used for self-clone/update.
ENTERPRISE_KIT_REPO="https://github.com/blackstraw-ai/ai-dev-kit.git"
ENTERPRISE_KIT_BRANCH="main"

# Agent skills are installed via `databricks aitools` (Databricks CLI v1.0.0+),
# exactly as the official upstream installer does.
MIN_AITOOLS_CLI_VERSION="1.0.0"

# MLflow skills fetched from mlflow/skills repo (tagless — main is intentional)
MLFLOW_SKILLS=(
    agent-evaluation
    analyze-mlflow-chat-session
    analyze-mlflow-trace
    instrumenting-with-mlflow-tracing
    mlflow-onboarding
    querying-mlflow-metrics
    retrieving-mlflow-traces
    searching-mlflow-docs
)
MLFLOW_BASE_URL="https://raw.githubusercontent.com/mlflow/skills/main"

# Hardcoded fallback for agent skills count (mirrors AGENT_B_STABLE_FALLBACK in
# the official installer). Used when `databricks aitools list` is unavailable
# (rate-limited, offline, or CLI too old). Keep in sync with upstream periodically.
AGENT_B_STABLE_FALLBACK=(
    databricks-agent-bricks        databricks-ai-functions        databricks-aibi-dashboards
    databricks-app-design          databricks-apps                databricks-apps-python
    databricks-core                databricks-dabs                databricks-data-discovery
    databricks-dbsql               databricks-docs                databricks-execution-compute
    databricks-iceberg             databricks-jobs                databricks-lakebase
    databricks-lakeflow-connect    databricks-metric-views        databricks-ml-training
    databricks-mlflow-evaluation   databricks-model-serving       databricks-pipelines
    databricks-python-sdk          databricks-serverless-migration databricks-spark-structured-streaming
    databricks-synthetic-data-gen  databricks-unity-catalog       databricks-unstructured-pdf-generation
    databricks-vector-search       databricks-zerobus-ingest
)
AGENT_B_EXPERIMENTAL_FALLBACK=(
    databricks-ai-runtime
    databricks-genie
    spark-python-data-source
)
_count() { echo $#; }

# =============================================================================
# ── PATHS  (derived — do not edit) ───────────────────────────────────────────
# =============================================================================

INSTALL_DIR="${AIDEVKIT_HOME:-$HOME/.ai-dev-kit}"

_raw_base="${ENTERPRISE_KIT_REPO%.git}"
_raw_base="${_raw_base/github.com/raw.githubusercontent.com}"
_RERUN_CMD="bash <(curl -sL ${_raw_base}/${ENTERPRISE_KIT_BRANCH}/enterprise_install_v2.sh)"

# Detect whether running from a local clone or via curl/pipe
_local_repo=""
if [ -f "$0" ] 2>/dev/null; then
    _maybe_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || true
    if [ -n "$_maybe_dir" ] \
       && [ -d "$_maybe_dir/databricks-mcp-server" ] \
       && [ -d "$_maybe_dir/databricks-tools-core" ]; then
        _local_repo="$_maybe_dir"
    fi
fi

if [ -n "$_local_repo" ]; then
    REPO_DIR="$_local_repo"
    _LOCAL_REPO_MODE=true
else
    REPO_DIR="$INSTALL_DIR/repo"
    _LOCAL_REPO_MODE=false
fi

VENV_DIR="$INSTALL_DIR/.venv"
VENV_PYTHON="$VENV_DIR/bin/python"
MCP_ENTRY="$REPO_DIR/databricks-mcp-server/run_server.py"
UPDATE_CHECK_CMD="bash $REPO_DIR/.claude-plugin/check_update.sh"

# =============================================================================
# ── DEFAULTS  (overridable by flags / env vars) ───────────────────────────────
# =============================================================================

PROFILE="${DEVKIT_PROFILE:-DEFAULT}"
SCOPE="${DEVKIT_SCOPE:-project}"
FORCE="${DEVKIT_FORCE:-false}"
INSTALL_MCP=true
INSTALL_SKILLS=true
SKILLS_ONLY=false
SILENT=false
PROFILE_PROVIDED=false

if [ "$FORCE"  = "true" ] || [ "$FORCE"  = "1" ]; then FORCE=true;  else FORCE=false;  fi
if [ "$SILENT" = "true" ] || [ "$SILENT" = "1" ]; then SILENT=true; else SILENT=false; fi

PROJECT_DIR=""
WORKSPACE_URL=""
MLFLOW_COUNT=0
AGENT_COUNT=0
_UC_SCHEMA=""
_UC_REGISTRY_OK=false

# =============================================================================
# ── PARSE FLAGS ───────────────────────────────────────────────────────────────
# =============================================================================

while [ $# -gt 0 ]; do
    case $1 in
        -p|--profile)     [ -z "${2:-}" ] && { echo "--profile requires a value" >&2; exit 1; }; PROFILE="$2"; PROFILE_PROVIDED=true; shift 2 ;;
        -g|--global)      SCOPE="global"; shift ;;
        --skills-only)    INSTALL_MCP=false; SKILLS_ONLY=true; shift ;;
        --mcp-only)       INSTALL_SKILLS=false; shift ;;
        --silent)         SILENT=true; shift ;;
        -f|--force)       FORCE=true; shift ;;
        -h|--help)
            echo ""
            echo "${ENTERPRISE_DISPLAY} Enterprise AI Dev Kit Installer v2"
            echo ""
            echo "Usage: bash enterprise_install_v2.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -p, --profile NAME     Databricks profile (default: DEFAULT)"
            echo "  -g, --global           Install globally (not per-project)"
            echo "  --skills-only          Fast path: only update skills (Steps 2 + 5 only)"
            echo "  --mcp-only             Skip skills installation"
            echo "  --silent               No output except errors"
            echo "  -f, --force            Force reinstall"
            echo ""
            echo "Environment variables:"
            echo "  DEVKIT_PROFILE         Databricks config profile"
            echo "  DEVKIT_FORCE           Set to 'true' to force reinstall"
            echo "  AIDEVKIT_HOME          Install dir (default: ~/.ai-dev-kit)"
            echo ""
            exit 0 ;;
        *) echo "Unknown option: $1 (use -h for help)" >&2; exit 1 ;;
    esac
done

# =============================================================================
# ── OUTPUT HELPERS ────────────────────────────────────────────────────────────
# =============================================================================

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[1m'; D='\033[2m'; N='\033[0m'; CY='\033[0;36m'

msg()  { [ "$SILENT" = true ] || echo -e "  $*"; }
ok()   { [ "$SILENT" = true ] || echo -e "  ${G}✓${N} $*"; }
warn() { [ "$SILENT" = true ] || echo -e "  ${Y}!${N} $*"; }
die()  { echo -e "  ${R}✗${N} $*" >&2; exit 1; }
step() { [ "$SILENT" = true ] || echo -e "\n${CY}────────────────────────────────────────────────────────${N}\n  ${B}$*${N}\n${CY}────────────────────────────────────────────────────────${N}\n"; }

# =============================================================================
# ── INTERACTIVE HELPERS ───────────────────────────────────────────────────────
# =============================================================================

is_interactive() {
    [ -t 0 ] || ( : < /dev/tty ) 2>/dev/null
}

version_gte() {
    printf '%s\n%s' "$2" "$1" | sort -V -C
}

prompt() {
    local text="$1" default="${2:-}" result=""
    if [ "$SILENT" = true ]; then echo "$default"; return; fi
    if is_interactive; then
        printf "  %b [%s]: " "$text" "$default" > /dev/tty
        read -r result < /dev/tty
    else
        echo "$default"; return
    fi
    [ -z "$result" ] && echo "$default" || echo "$result"
}

# ---------------------------------------------------------------------------
# radio_select — arrow-key single-choice selector
#
# Usage : radio_select "Title" "label1|value1|hint1" "label2|value2|hint2" ...
# Output: echoes the VALUE of the selected item to stdout
# Falls back to a numbered list when not running in a TTY.
# ---------------------------------------------------------------------------
radio_select() {
    local title="$1"; shift
    local -a labels=() values=() hints=()
    local count=0

    for item in "$@"; do
        IFS='|' read -r label value hint <<< "$item"
        labels+=("$label"); values+=("$value"); hints+=("$hint")
        count=$((count + 1))
    done

    local total_rows=$((count + 2))
    local cursor=0

    if ! is_interactive || [ "$SILENT" = true ]; then
        printf "  %b%s%b\n" "$B" "$title" "$N" > /dev/tty 2>/dev/null || true
        local j=0
        for label in "${labels[@]}"; do
            printf "    %d) %s\n" $((j+1)) "$label"
            j=$((j+1))
        done > /dev/tty
        printf "  Enter number [1]: " > /dev/tty
        local choice; read -r choice < /dev/tty
        local idx=$(( ${choice:-1} - 1 ))
        [ "$idx" -lt 0 ] && idx=0
        [ "$idx" -ge "$count" ] && idx=0
        echo "${values[$idx]}"
        return
    fi

    _radio_draw() {
        printf "\033[%dA" "$total_rows" > /dev/tty
        local i=0
        for i in $(seq 0 $((count - 1))); do
            local arrow="    " dot="${D}○${N}" hint_col="$D"
            [ "$i" = "$cursor" ] && arrow="  ${CY}❯${N} " && dot="${G}●${N}" && hint_col="$G"
            printf "\033[2K  %b%b%-24s %b%s%b\n" \
                "$arrow" "$dot " "${labels[$i]}" "$hint_col" "${hints[$i]}" "$N" > /dev/tty
        done
        printf "\033[2K\n" > /dev/tty
        if [ "$cursor" = "$count" ]; then
            printf "\033[2K  ${CY}❯${N} ${G}${B}[ Confirm ]${N}\n" > /dev/tty
        else
            printf "\033[2K    ${D}[ Confirm ]${N}\n" > /dev/tty
        fi
    }

    printf "\n  %b%s%b\n  %b↑/↓ navigate · Enter confirm%b\n\n" \
        "$B" "$title" "$N" "$D" "$N" > /dev/tty
    for _ in $(seq 0 $((total_rows - 1))); do printf "\n" > /dev/tty; done

    printf "\033[?25l" > /dev/tty
    trap 'printf "\033[?25h" > /dev/tty 2>/dev/null' EXIT

    _radio_draw

    while true; do
        local key=""
        IFS= read -rsn1 key < /dev/tty 2>/dev/null
        if [ "$key" = $'\x1b' ]; then
            local s1="" s2=""
            IFS= read -rsn1 s1 < /dev/tty 2>/dev/null
            IFS= read -rsn1 s2 < /dev/tty 2>/dev/null
            if [ "$s1" = "[" ]; then
                case "$s2" in
                    A) [ "$cursor" -gt 0 ]      && cursor=$((cursor - 1)) ;;
                    B) [ "$cursor" -lt "$count" ] && cursor=$((cursor + 1)) ;;
                esac
            fi
        elif [ "$key" = "" ]; then
            _radio_draw; break
        fi
        _radio_draw
    done

    printf "\033[?25h" > /dev/tty
    trap - EXIT
    echo "${values[$cursor]}"
}

# Extract user email from 'databricks current-user me --output json' output.
# OAuth logins put email in userName; PAT logins put it in emails[].value.
_dbx_user() {
    local json="$1"
    echo "$json" | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    u = d.get('userName','')
    if '@' in u: print(u); sys.exit(0)
    for e in d.get('emails', []):
        v = e.get('value','')
        if '@' in v: print(v); sys.exit(0)
    if u: print(u)
except: pass
" 2>/dev/null || true
}

# =============================================================================
# ── BANNER ────────────────────────────────────────────────────────────────────
# =============================================================================

echo ""
_banner_title="   ${ENTERPRISE_DISPLAY} — Enterprise AI Dev Kit Installer v2"
_banner_inner=56
_title_len=${#_banner_title}
[ "$_title_len" -gt "$_banner_inner" ] && _banner_inner=$(( _title_len + 2 ))
_border="$(printf '═%.0s' $(seq 1 "$_banner_inner"))"
_pad=$(( _banner_inner - _title_len ))
_banner_padded="${_banner_title}$(printf '%*s' "$_pad" '')"
printf "${CY}╔%s╗${N}\n" "$_border"
printf "${CY}║${N}%s${CY}║${N}\n" "$_banner_padded"
printf "${CY}╚%s╝${N}\n" "$_border"
echo ""
warn "NOTE: Do NOT run the official Databricks install.sh alongside this script."
msg  "  This enterprise installer fully replaces it. Running both will break the MCP config."
echo ""

# =============================================================================
# ── REPO SETUP ────────────────────────────────────────────────────────────────
# =============================================================================

if [ "$_LOCAL_REPO_MODE" = true ]; then
    ok "Using local repo  →  $REPO_DIR"
else
    if ! command -v git >/dev/null 2>&1; then
        echo "" >&2
        echo "  ✗ git not found — run prerequisites first:" >&2
        echo "    bash ${_raw_base}/${ENTERPRISE_KIT_BRANCH}/prerequisites.sh" >&2
        echo "" >&2
        exit 1
    fi
    msg "Checking enterprise kit repo..."
    mkdir -p "$INSTALL_DIR"
    if [ -d "$REPO_DIR/.git" ]; then
        git -C "$REPO_DIR" fetch -q --depth 1 origin "$ENTERPRISE_KIT_BRANCH" 2>/dev/null \
            && git -C "$REPO_DIR" reset -q --hard FETCH_HEAD \
            && ok "Enterprise kit updated  →  $REPO_DIR" \
            || warn "Could not update enterprise kit — using existing version"
    else
        git clone -q --depth 1 --branch "$ENTERPRISE_KIT_BRANCH" \
            "$ENTERPRISE_KIT_REPO" "$REPO_DIR" \
            && ok "Enterprise kit ready  →  $REPO_DIR" \
            || { echo "  ✗ Failed to clone enterprise kit from: $ENTERPRISE_KIT_REPO" >&2; exit 1; }
    fi
fi
echo ""

# =============================================================================
# ── STEP 1: PROJECT DIRECTORY ─────────────────────────────────────────────────
# =============================================================================

if [ "$SKILLS_ONLY" = true ]; then
    PROJECT_DIR="$(pwd)"
    ok "Project dir: $PROJECT_DIR"
else
    step "Step 1 of 6 — Project Directory"
    PROJECT_DIR=$(prompt "Project directory" "$(pwd)")
    # Strip trailing slashes / backslashes (tty buffer noise after arrow-key navigation)
    PROJECT_DIR="$(echo "$PROJECT_DIR" | sed 's|[/\\]*$||')"
    [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$(pwd)"
    mkdir -p "$PROJECT_DIR"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    ok "Project dir: $PROJECT_DIR"
fi

mkdir -p "$PROJECT_DIR/.claude/skills"
ok "Workspace directories created"

# =============================================================================
# ── STEP 2: PREREQUISITES ─────────────────────────────────────────────────────
# =============================================================================

step "Step 2 of 6 — Prerequisites"

_PREREQ_SCRIPT="${_raw_base}/${ENTERPRISE_KIT_BRANCH}/prerequisites.sh"

if command -v git >/dev/null 2>&1; then
    ok "$(git --version)"
else
    die "git not found. Run prerequisites first:  bash <(curl -sL ${_PREREQ_SCRIPT})"
fi

if [ "$SKILLS_ONLY" = false ]; then

    if command -v uv >/dev/null 2>&1; then
        ok "uv $(uv --version)"
    else
        die "uv not found. Run prerequisites first:  bash <(curl -sL ${_PREREQ_SCRIPT})"
    fi

    # -- Databricks CLI ----------------------------------------------------------
    if command -v databricks >/dev/null 2>&1; then
        ok "Databricks CLI: $(databricks --version 2>&1 | head -1)"
    else
        warn "Databricks CLI not found — installing..."
        if command -v brew >/dev/null 2>&1; then
            brew tap databricks/tap 2>/dev/null || true
            brew install databricks --quiet \
                && ok "Databricks CLI: $(databricks --version 2>&1 | head -1) (just installed)" \
                || { warn "brew install failed — trying curl installer..."
                     curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh || true; }
        else
            curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh || true
        fi

        if command -v databricks >/dev/null 2>&1; then
            ok "Databricks CLI installed  ($(databricks --version 2>&1 | head -1))"
        else
            warn "Databricks CLI install may have failed — install manually:"
            warn "  https://docs.databricks.com/dev-tools/cli/install.html"
        fi
    fi

fi  # end SKILLS_ONLY skip

# =============================================================================
# ── STEP 3: DATABRICKS WORKSPACE & PROFILE ────────────────────────────────────
# =============================================================================

if [ "$SKILLS_ONLY" = false ]; then

step "Step 3 of 6 — Databricks Workspace & Profile"

# -- Profile selection from ~/.databrickscfg or create new --------------------
_dbx_cfg="$HOME/.databrickscfg"
_known_profiles=()

if [ -f "$_dbx_cfg" ]; then
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            _known_profiles+=("${BASH_REMATCH[1]}")
        fi
    done < "$_dbx_cfg"
fi

if [ ${#_known_profiles[@]} -gt 0 ] && [ "$PROFILE_PROVIDED" = false ] && [ "$SILENT" = false ]; then
    # Build radio items: existing profiles + "Enter workspace URL (create new)" option
    _radio_items=()
    for _p in "${_known_profiles[@]}"; do
        _hint=""; [ "$_p" = "DEFAULT" ] && _hint="default"
        _radio_items+=("${_p}|${_p}|${_hint}")
    done
    _radio_items+=("Create new profile...|__NEW__|enter workspace URL and profile name")

    PROFILE=$(radio_select "Choose Databricks profile:" "${_radio_items[@]}")
fi

if [ "$PROFILE" = "__NEW__" ] || [ ${#_known_profiles[@]} -eq 0 ]; then
    echo ""
    WORKSPACE_URL=$(prompt "Databricks workspace URL" "https://")
    WORKSPACE_URL="${WORKSPACE_URL%/}"
    PROFILE=$(prompt "Profile name" "DEFAULT")
    echo ""
    msg "Authenticating with Databricks workspace..."
    if command -v databricks >/dev/null 2>&1; then
        databricks auth login --host "$WORKSPACE_URL" --profile "$PROFILE" || \
            warn "Authentication window may have failed — re-run: databricks auth login --host $WORKSPACE_URL --profile $PROFILE"
    fi
else
    # Derive workspace URL from existing profile
    WORKSPACE_URL=""
    if [ -f "$_dbx_cfg" ]; then
        _in_profile=false
        while IFS= read -r _line; do
            if [[ "$_line" =~ ^\[${PROFILE}\]$ ]]; then
                _in_profile=true
            elif [[ "$_line" =~ ^\[ ]]; then
                _in_profile=false
            elif [ "$_in_profile" = true ] && [[ "$_line" =~ ^host[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                WORKSPACE_URL="${BASH_REMATCH[1]}"
                WORKSPACE_URL="${WORKSPACE_URL%/}"
                break
            fi
        done < "$_dbx_cfg"
    fi

    ok "Profile: $PROFILE"
    [ -n "$WORKSPACE_URL" ] && ok "Workspace: $WORKSPACE_URL"

    # Verify / refresh auth
    if command -v databricks >/dev/null 2>&1; then
        _auth_json="$(databricks current-user me --profile "$PROFILE" --output json 2>/dev/null || true)"
        _auth_user="$(_dbx_user "$_auth_json")"
        if [ -n "$_auth_user" ]; then
            ok "Already authenticated as $_auth_user"
        else
            warn "Not authenticated — opening browser for OAuth login..."
            [ -z "$WORKSPACE_URL" ] && WORKSPACE_URL=$(prompt "Workspace URL for profile '$PROFILE'" "https://")
            databricks auth login --host "$WORKSPACE_URL" --profile "$PROFILE" || \
                warn "Authentication may have failed — re-run: databricks auth login --host $WORKSPACE_URL --profile $PROFILE"
            _auth_json2="$(databricks current-user me --profile "$PROFILE" --output json 2>/dev/null || true)"
            _auth_user2="$(_dbx_user "$_auth_json2")"
            [ -n "$_auth_user2" ] && ok "Authenticated as $_auth_user2"
        fi
    fi
fi

fi  # end SKILLS_ONLY skip

# =============================================================================
# ── STEP 4: DATABRICKS MCP ────────────────────────────────────────────────────
# =============================================================================

if [ "$INSTALL_MCP" = true ]; then
    step "Step 4 of 6 — Databricks MCP"
    msg "Setting up Databricks MCP server..."

    if [ ! -d "$REPO_DIR/databricks-mcp-server" ]; then
        die "databricks-mcp-server not found in $REPO_DIR"
    fi

    # Create venv and install packages
    mkdir -p "$VENV_DIR"
    if ! uv venv --python 3.11 --allow-existing "$VENV_DIR" -q 2>/dev/null; then
        uv venv --allow-existing "$VENV_DIR" -q
    fi
    msg "Installing Python dependencies..."
    uv pip install --python "$VENV_PYTHON" --native-tls \
        -e "$REPO_DIR/databricks-tools-core" \
        -e "$REPO_DIR/databricks-mcp-server" --quiet

    "$VENV_PYTHON" -c "import databricks_mcp_server" 2>/dev/null \
        || die "MCP server import failed after install."

    ok "MCP server ready  →  $VENV_DIR"

    # Write .mcp.json
    _MCP_CONFIG="$PROJECT_DIR/.mcp.json"
    python3 - <<PYEOF
import json, pathlib
path = pathlib.Path('${_MCP_CONFIG}')
existing = {}
if path.exists():
    try: existing = json.loads(path.read_text())
    except: pass
existing.setdefault('mcpServers', {})['databricks'] = {
    'command': '${VENV_PYTHON}',
    'args':    ['${MCP_ENTRY}'],
    'defer_loading': True,
    'env': {'DATABRICKS_CONFIG_PROFILE': '${PROFILE}'}
}
path.write_text(json.dumps(existing, indent=2) + '\n')
PYEOF
    ok "Databricks MCP  →  $_MCP_CONFIG"
fi

_MCP_CONFIG="$PROJECT_DIR/.mcp.json"

# =============================================================================
# ── STEP 5: SKILLS + SETTINGS ─────────────────────────────────────────────────
# =============================================================================

step "Step 5 of 6 — Skills + Settings"

# -- Write .claude/settings.json with SessionStart hook -----------------------
_SETTINGS_PATH="$PROJECT_DIR/.claude/settings.json"
mkdir -p "$PROJECT_DIR/.claude"

python3 - <<PYEOF
import json, pathlib
path = pathlib.Path('${_SETTINGS_PATH}')
existing = {}
if path.exists():
    try: existing = json.loads(path.read_text())
    except: pass
hook_cmd = '${UPDATE_CHECK_CMD}'
hooks = existing.setdefault('hooks', {})
session = hooks.setdefault('SessionStart', [])
if not any('check_update' in str(h) for g in session for h in g.get('hooks', [])):
    session.append({'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 5}]})
path.write_text(json.dumps(existing, indent=2) + '\n')
PYEOF
ok ".claude/settings.json  →  $_SETTINGS_PATH"

# -- Install skills ------------------------------------------------------------
if [ "$INSTALL_SKILLS" = true ]; then
    echo ""
    msg "Installing skills..."
    SKILLS_DEST="$PROJECT_DIR/.claude/skills"
    mkdir -p "$SKILLS_DEST"

    _adk="$PROJECT_DIR/.ai-dev-kit"
    mkdir -p "$_adk"
    : > "$_adk/.installed-skills"

    # -- MLflow skills from mlflow/skills repo ---------------------------------
    MLFLOW_COUNT=0
    msg "Fetching MLflow skills..."
    for _skill in "${MLFLOW_SKILLS[@]}"; do
        _dest="$SKILLS_DEST/$_skill"
        mkdir -p "$_dest"
        # --retry 2 handles transient drops; sleep 0.5 between skills avoids burst on slow networks
        if curl -fsSL --retry 2 --retry-delay 1 "$MLFLOW_BASE_URL/$_skill/SKILL.md" -o "$_dest/SKILL.md" 2>/dev/null; then
            for _ref in reference.md examples.md api.md; do
                curl -fsSL --retry 1 "$MLFLOW_BASE_URL/$_skill/$_ref" -o "$_dest/$_ref" 2>/dev/null || true
            done
            echo "$SKILLS_DEST|$_skill" >> "$_adk/.installed-skills"
            MLFLOW_COUNT=$((MLFLOW_COUNT + 1))
        else
            rm -rf "$_dest"
            warn "Could not fetch MLflow skill: $_skill (re-run with --skills-only once rate limit clears)"
        fi
        sleep 0.5
    done
    ok "MLflow skills  ($MLFLOW_COUNT installed)"

    # -- Agent skills via databricks aitools ------------------------------------
    # Follows the official ai-dev-kit flow exactly:
    #   1. Count expected skills from live inventory
    #   2. Ensure Claude plugin marketplace is registered (required before aitools runs)
    #   3. Run `databricks aitools install` (plugin install for Claude Code)
    #   4. Verify the plugin actually registered
    AGENT_COUNT=0
    _aitools_ok=false
    _cli_ver=""
    if command -v databricks >/dev/null 2>&1; then
        _cli_ver="$(databricks --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    fi
    if [ -n "$_cli_ver" ] && version_gte "$_cli_ver" "$MIN_AITOOLS_CLI_VERSION"; then
        _aitools_ok=true
    fi

    if [ "$_aitools_ok" = true ]; then
        # Ensure Claude Code plugin marketplace is registered before aitools runs.
        # Without this, `databricks aitools install --agents claude-code` silently
        # fails to install the plugin even though it exits 0.
        if command -v claude >/dev/null 2>&1; then
            _mp="claude-plugins-official"
            _mp_present="$(claude plugin marketplace list 2>/dev/null | grep -F "$_mp" || true)"
            if [ -z "$_mp_present" ]; then
                msg "Registering Claude plugin marketplace..."
                claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 \
                    || warn "Could not register Claude marketplace — plugin install may fail"
            else
                claude plugin marketplace update "$_mp" >/dev/null 2>&1 || true
            fi
        fi

        # Install agent skills as a Claude Code plugin (+ experimental skills)
        _aitools_out="$(databricks aitools install --scope project --agents claude-code --experimental -p "$PROFILE" 2>&1)" \
            && _aitools_rc=0 || _aitools_rc=$?

        if [ "$_aitools_rc" -eq 0 ]; then
            # Count from the fallback list (mirrors official installer's _count approach).
            # aitools installs the full set; the fallback list is the known stable set.
            AGENT_COUNT=$(_count "${AGENT_B_STABLE_FALLBACK[@]}" "${AGENT_B_EXPERIMENTAL_FALLBACK[@]}")
            ok "Agent skills  ($AGENT_COUNT installed via databricks aitools)"
            # Verify the Claude plugin actually registered
            if command -v claude >/dev/null 2>&1; then
                _plugin_check="$(claude plugin list --json 2>/dev/null | grep -o '"databricks@claude-plugins-official"' | head -1 || \
                                 claude plugin list 2>/dev/null | grep -F 'databricks@claude-plugins-official' || true)"
                if [ -z "$_plugin_check" ]; then
                    warn "Claude plugin not confirmed — run manually if skills are missing:"
                    warn "  claude plugin install databricks@claude-plugins-official --scope project"
                fi
            fi
        else
            warn "databricks aitools install failed — agent skills not installed"
            if echo "$_aitools_out" | grep -qiE "429|rate.limit|fetch manifest"; then
                warn "  Cause: GitHub rate limit — wait ~1 min and re-run: $_RERUN_CMD --skills-only"
            else
                warn "  Run manually: databricks aitools install --scope project --agents claude-code --experimental -p $PROFILE"
            fi
            AGENT_COUNT=0
        fi
    else
        warn "Agent skills skipped — Databricks CLI v${MIN_AITOOLS_CLI_VERSION}+ required"
        [ -n "$_cli_ver" ] && warn "  Found: v${_cli_ver}" || warn "  Databricks CLI not found"
        warn "  Upgrade: curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh"
        warn "  Then re-run: $_RERUN_CMD"
    fi

    # -- UC Skill Registry via ucode -------------------------------------------
    # Discovers which catalog.schema in this workspace contains UC skills,
    # then wires the databricks-skill-registry MCP server into .mcp.json so
    # enterprise skills load live without any local file copies.
    msg "Setting up UC Skill Registry..."

    _ucode_ok=false
    if command -v ucode >/dev/null 2>&1; then
        ok "ucode $(ucode --version 2>/dev/null | head -1 || echo 'found')"
        _ucode_ok=true
    elif command -v uv >/dev/null 2>&1; then
        msg "Installing ucode..."
        uv tool install git+https://github.com/databricks/ucode --quiet 2>/dev/null \
            && ok "ucode installed" && _ucode_ok=true \
            || warn "ucode install failed — UC skill registry skipped"
    else
        warn "uv not found — cannot install ucode, UC skill registry skipped"
    fi

    if [ "$_ucode_ok" = true ] && command -v databricks >/dev/null 2>&1; then
        # In --skills-only mode Step 3 is skipped; derive workspace URL from profile config
        if [ -z "$WORKSPACE_URL" ] && [ -f "$HOME/.databrickscfg" ]; then
            _in_p=false
            while IFS= read -r _l; do
                [[ "$_l" =~ ^\[${PROFILE}\]$ ]] && _in_p=true && continue
                [[ "$_l" =~ ^\[             ]] && _in_p=false
                [ "$_in_p" = true ] && [[ "$_l" =~ ^host[[:space:]]*=[[:space:]]*(.+)$ ]] \
                    && WORKSPACE_URL="${BASH_REMATCH[1]%/}" && break
            done < "$HOME/.databrickscfg"
        fi

        # Auto-discover schemas that contain UC skills (Option C)
        msg "Scanning workspace for UC skill schemas..."
        _discovered="$(python3 - "$PROFILE" 2>/dev/null <<'PYEOF'
import subprocess, json, sys
profile = sys.argv[1]
def dbx(path):
    r = subprocess.run(["databricks","api","get",path,"--profile",profile],
                       capture_output=True, text=True, timeout=15)
    if r.returncode != 0: return None
    try: return json.loads(r.stdout)
    except: return None
cats = (dbx("/api/2.1/unity-catalog/catalogs") or {}).get("catalogs", [])
found = []
for c in cats:
    cn = c.get("name","")
    for s in (dbx(f"/api/2.1/unity-catalog/schemas?catalog_name={cn}") or {}).get("schemas",[]):
        sn = s.get("name","")
        if sn == "information_schema": continue
        if (dbx(f"/api/2.1/unity-catalog/skills?parent=schemas/{cn}.{sn}") or {}).get("skills"):
            found.append(f"{cn}.{sn}")
print("\n".join(found))
PYEOF
)" || true

        _schema_count=0
        [ -n "$_discovered" ] && _schema_count="$(echo "$_discovered" | wc -l | tr -d ' ')"

        if [ "$_schema_count" -eq 0 ] 2>/dev/null; then
            warn "No UC skill schemas found in this workspace"
            _UC_SCHEMA="$(prompt "Enter skill schema manually (catalog.schema) or leave blank to skip" "")"
        elif [ "$_schema_count" -eq 1 ]; then
            _UC_SCHEMA="$_discovered"
            ok "Found skill schema: $_UC_SCHEMA"
            _confirm="$(prompt "Use this schema? (y/n)" "y")"
            [ "$_confirm" != "y" ] && [ "$_confirm" != "Y" ] && _UC_SCHEMA=""
        else
            _radio_items=()
            while IFS= read -r _s; do
                [ -n "$_s" ] && _radio_items+=("$_s|$_s|")
            done <<< "$_discovered"
            _radio_items+=("Skip|__SKIP__|do not configure UC skill registry")
            _UC_SCHEMA="$(radio_select "Choose UC skill schema:" "${_radio_items[@]}")"
            [ "$_UC_SCHEMA" = "__SKIP__" ] && _UC_SCHEMA=""
        fi

        if [ -n "$_UC_SCHEMA" ]; then
            # Merge databricks-skill-registry entry into .mcp.json (same pattern as Step 4)
            _mcp_fwd="$PROJECT_DIR/.mcp.json"
            python3 - <<PYEOF
import json, pathlib
path = pathlib.Path('${_mcp_fwd}')
existing = {}
if path.exists():
    try: existing = json.loads(path.read_text())
    except: pass
existing.setdefault('mcpServers', {})['databricks-skill-registry'] = {
    'command': 'uvx',
    'args': ['databricks-skill-registry'],
    'env': {
        'DATABRICKS_HOST': '${WORKSPACE_URL}',
        'DATABRICKS_CONFIG_PROFILE': '${PROFILE}',
        'SKILL_REGISTRY_SCOPES': '${_UC_SCHEMA}'
    }
}
path.write_text(json.dumps(existing, indent=2) + '\n')
PYEOF
            ok "UC Skill Registry  →  $_UC_SCHEMA (live MCP)"
            _UC_REGISTRY_OK=true
            # Persist schema so --skills-only re-runs can confirm/update it
            echo "$_UC_SCHEMA" > "$_adk/.skills-schema"
        fi
    fi

    # -- Genie sync (optional) -------------------------------------------------
    if command -v databricks >/dev/null 2>&1; then
        _genie_json="$(databricks current-user me --profile "$PROFILE" --output json 2>/dev/null || true)"
        _genie_user="$(_dbx_user "$_genie_json")"

        if [ -n "$_genie_user" ]; then
            echo ""
            _do_genie=$(prompt "Would you like to upload Skills to Genie Code? (y/n)" "y")
            if [ "$_do_genie" = "y" ] || [ "$_do_genie" = "Y" ]; then
                _genie_target="/Workspace/Users/${_genie_user}/.assistant/skills"
                echo ""
                msg "Workspace user: $_genie_user"
                msg "Workspace path: $_genie_target"
                echo ""
                databricks workspace mkdirs "$_genie_target" --profile "$PROFILE" 2>/dev/null || true
                _genie_fail=0
                for _skill_dir in "$SKILLS_DEST"/*/; do
                    _skill_name="$(basename "$_skill_dir")"
                    msg "Uploading $_skill_name"
                    databricks workspace import-dir "$_skill_dir" \
                        "$_genie_target/$_skill_name" \
                        --overwrite --profile "$PROFILE" 2>/dev/null \
                        || _genie_fail=$((_genie_fail + 1))
                done
                echo ""
                if [ "$_genie_fail" = 0 ]; then
                    ok "Skills synced to Databricks Genie  →  $_genie_target"
                else
                    warn "$_genie_fail skill(s) failed to sync — check manually at: $_genie_target"
                fi
            fi
        fi
    fi
fi  # end INSTALL_SKILLS

# =============================================================================
# ── STEP 6: WORKSPACE + VERSION LOCK ─────────────────────────────────────────
# =============================================================================

if [ "$SKILLS_ONLY" = false ]; then

step "Step 6 of 6 — Workspace"

_adk="$PROJECT_DIR/.ai-dev-kit"
mkdir -p "$_adk"

# version
_adk_ver="enterprise"
[ -f "$REPO_DIR/VERSION" ] && _adk_ver="$(cat "$REPO_DIR/VERSION" | tr -d '[:space:]')"
echo "$_adk_ver" > "$_adk/version"
ok ".ai-dev-kit/version  ($_adk_ver)"

[ -f "$_adk/.installed-skills" ] || touch "$_adk/.installed-skills"
ok ".ai-dev-kit/.installed-skills"

echo "enterprise" > "$_adk/.skills-profile"
ok ".ai-dev-kit/.skills-profile"

# -- .gitignore ----------------------------------------------------------------
_GITIGNORE="$PROJECT_DIR/.gitignore"
touch "$_GITIGNORE"
for _rule in ".ai-dev-kit/" ".claude/" ".mcp.json" ".env" "__pycache__/" "*.pyc"; do
    grep -qF "$_rule" "$_GITIGNORE" 2>/dev/null || echo "$_rule" >> "$_GITIGNORE"
done
ok ".gitignore updated"

fi  # end SKILLS_ONLY skip

# =============================================================================
# ── SUMMARY ───────────────────────────────────────────────────────────────────
# =============================================================================

echo ""
if [ "$SKILLS_ONLY" = true ]; then
    printf "${G}%s${N}\n" "+========================================================+"
    printf "${G}%s${N}\n" "|   ✓  Skills Updated                                    |"
    printf "${G}%s${N}\n" "+========================================================+"
    echo ""
    printf "  %-20s %s\n" "Project"           "$PROJECT_DIR"
    printf "  %-20s %s\n" "MLflow skills"     "$MLFLOW_COUNT installed"
    printf "  %-20s %s\n" "Agent skills"      "$AGENT_COUNT installed"
    [ "$_UC_REGISTRY_OK" = true ] && printf "  %-20s %s\n" "UC skill registry" "$_UC_SCHEMA (live)"
else
    printf "${G}%s${N}\n" "+========================================================+"
    printf "${G}%s${N}\n" "|   ✓  Workspace Ready                                   |"
    printf "${G}%s${N}\n" "+========================================================+"
    echo ""
    printf "  %-20s %s\n" "Project"           "$PROJECT_DIR"
    printf "  %-20s %s\n" "Enterprise"        "$ENTERPRISE_DISPLAY"
    printf "  %-20s %s\n" "Workspace"         "$WORKSPACE_URL"
    printf "  %-20s %s\n" "Profile"           "$PROFILE"
    printf "  %-20s %s\n" "MLflow skills"     "$MLFLOW_COUNT installed"
    printf "  %-20s %s\n" "Agent skills"      "$AGENT_COUNT installed"
    [ "$_UC_REGISTRY_OK" = true ] && printf "  %-20s %s\n" "UC skill registry" "$_UC_SCHEMA (live)"
    printf "  %-20s %s\n" "MCP config"        "$_MCP_CONFIG"
fi
echo ""
printf "${CY}Next steps:${N}\n"
printf "  1. Open your project in Claude Code:  ${B}claude %s${N}\n" "$PROJECT_DIR"
printf "  2. MCP + skills are active — try: \"List my SQL warehouses\"\n"
[ "$_UC_REGISTRY_OK" = true ] && printf "  3. Enterprise skills live — try: \"List the skills in $_UC_SCHEMA\"\n"
echo ""
