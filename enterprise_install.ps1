#
# Blackstraw Enterprise AI Dev Kit — Installer (Windows)
#
# 6-step setup: project dir, prerequisites, workspace/profile, MCP server,
# skills (all upstream profiles), Claude settings + Genie sync, state files.
#
# Usage:
#   .\enterprise_install.ps1 [OPTIONS]
#   irm https://raw.githubusercontent.com/blackstraw-ai/ai-dev-kit/main/enterprise_install.ps1 | iex
#
# Options:
#   --profile / -p NAME      Databricks profile (default: DEFAULT)
#   --global  / -g           Install globally (not per-project)
#   --skills-only            Fast path: only update skills (Steps 2 + 5 only)
#   --mcp-only               Skip skills installation
#   --silent                 No output except errors
#   --force   / -f           Force reinstall
#
# Environment overrides:
#   $env:DEVKIT_PROFILE      Databricks config profile
#   $env:DEVKIT_FORCE        Set to 'true' to force reinstall
#   $env:DEVKIT_SKILLS_ONLY  Set to 'true' for skills-only mode
#   $env:AIDEVKIT_HOME       Install dir (default: ~/.ai-dev-kit)
#

$ErrorActionPreference = "Stop"

# =============================================================================
# -- ENTERPRISE CONFIGURATION  (edit this section for your organisation) ------
# =============================================================================

$ENTERPRISE_NAME    = "Blackstraw"
$ENTERPRISE_DISPLAY = "Blackstraw"

# GitHub URL for this enterprise installer repo — used for self-clone/update.
$ENTERPRISE_KIT_REPO   = "https://github.com/blackstraw-ai/ai-dev-kit.git"
$ENTERPRISE_KIT_BRANCH = "main"

# Agent skills are installed via `databricks aitools` (Databricks CLI v1.0.0+),
# exactly as the official upstream installer does.
$MIN_AITOOLS_CLI_VERSION = "1.0.0"

# MLflow skills fetched from mlflow/skills repo (tagless — main is intentional)
$MLFLOW_SKILLS = @(
    "agent-evaluation", "analyze-mlflow-chat-session", "analyze-mlflow-trace",
    "instrumenting-with-mlflow-tracing", "mlflow-onboarding",
    "querying-mlflow-metrics", "retrieving-mlflow-traces", "searching-mlflow-docs"
)
$MLFLOW_BASE_URL = "https://raw.githubusercontent.com/mlflow/skills/main"

# Hardcoded fallback for agent skills count (mirrors AGENT_B_STABLE_FALLBACK in
# the official installer). Used when `databricks aitools list` is unavailable.
# Keep in sync with upstream periodically.
$AGENT_B_STABLE_FALLBACK = @(
    "databricks-agent-bricks","databricks-ai-functions","databricks-aibi-dashboards",
    "databricks-app-design","databricks-apps","databricks-apps-python","databricks-core",
    "databricks-dabs","databricks-data-discovery","databricks-dbsql","databricks-docs",
    "databricks-execution-compute","databricks-iceberg","databricks-jobs",
    "databricks-lakebase","databricks-lakeflow-connect","databricks-metric-views",
    "databricks-ml-training","databricks-mlflow-evaluation","databricks-model-serving",
    "databricks-pipelines","databricks-python-sdk","databricks-serverless-migration",
    "databricks-spark-structured-streaming","databricks-synthetic-data-gen",
    "databricks-unity-catalog","databricks-unstructured-pdf-generation",
    "databricks-vector-search","databricks-zerobus-ingest"
)
$AGENT_B_EXPERIMENTAL_FALLBACK = @("databricks-ai-runtime","databricks-genie","spark-python-data-source")

# Enterprise-specific private skills repo.
# Set to the SSH or HTTPS clone URL of your private skills repository.
# Leave empty ("") to skip enterprise skills installation.
#
# Examples:
#   $ENTERPRISE_SKILLS_REPO = "git@github.com:blackstraw-ai/blackstraw-data-architecture-skills.git"
#   $ENTERPRISE_SKILLS_REPO = "https://github.com/blackstraw-ai/DAIA-data-architecture-skills.git"
#
$ENTERPRISE_SKILLS_REPO = ""

# Subfolder inside the repo that contains the skill folders (leave empty = repo root).
# Example: "blackstraw-data-architecture-skills"
$ENTERPRISE_SKILLS_REPO_SUBPATH = ""

# =============================================================================
# -- PATHS  (derived - do not edit) -------------------------------------------
# =============================================================================

$INSTALL_DIR  = if ($env:AIDEVKIT_HOME) { $env:AIDEVKIT_HOME } else { Join-Path $env:USERPROFILE ".ai-dev-kit" }

# Directory where the skills repo will be cloned locally (derived from $INSTALL_DIR above).
$ENTERPRISE_SKILLS_REPO_DIR = Join-Path $INSTALL_DIR "${ENTERPRISE_NAME}-skills-repo"

$_raw_base    = $ENTERPRISE_KIT_REPO -replace '\.git$', '' -replace 'github\.com', 'raw.githubusercontent.com'
$_RERUN_CMD   = "`$env:DEVKIT_SKILLS_ONLY='true'; irm ${_raw_base}/${ENTERPRISE_KIT_BRANCH}/enterprise_install.ps1 | iex"

# Detect local repo vs irm/pipe execution
$_LOCAL_REPO_MODE = $false
$REPO_DIR         = Join-Path $INSTALL_DIR "repo"
try {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ($ScriptDir -and
        (Test-Path (Join-Path $ScriptDir "databricks-mcp-server")) -and
        (Test-Path (Join-Path $ScriptDir "databricks-tools-core"))) {
        $REPO_DIR         = $ScriptDir
        $_LOCAL_REPO_MODE = $true
    }
} catch {}

$VENV_DIR    = Join-Path $INSTALL_DIR ".venv"
$VENV_PYTHON = Join-Path $VENV_DIR "Scripts\python.exe"
$MCP_ENTRY   = Join-Path $REPO_DIR "databricks-mcp-server\run_server.py"
$UPDATE_CHECK_CMD = "powershell -ExecutionPolicy Bypass -File `"$(Join-Path $REPO_DIR '.claude-plugin\check_update.ps1')`""

# =============================================================================
# -- DEFAULTS  (overridable by flags / env vars) --------------------------------
# =============================================================================

$script:PROFILE_         = if ($env:DEVKIT_PROFILE)    { $env:DEVKIT_PROFILE }    else { "DEFAULT" }
$script:SCOPE            = "project"
$script:FORCE            = ($env:DEVKIT_FORCE    -in @("true","1"))
$script:INSTALL_MCP      = $true
$script:INSTALL_SKILLS   = $true
$script:SKILLS_ONLY      = ($env:DEVKIT_SKILLS_ONLY -in @("true","1"))
$script:SILENT           = $false
$script:PROFILE_PROVIDED = $false
$script:PROJECT_DIR      = ""
$script:WORKSPACE_URL    = ""

$MLFLOW_COUNT    = 0
$AGENT_COUNT     = 0
$blkSkillCount   = 0

# =============================================================================
# -- PARSE FLAGS ---------------------------------------------------------------
# =============================================================================

$i = 0
while ($i -lt $args.Count) {
    switch -Regex ($args[$i]) {
        '^(-p|--profile)$' {
            if ($i + 1 -ge $args.Count) { Write-Error "--profile requires a value"; exit 1 }
            $script:PROFILE_ = $args[$i + 1]; $script:PROFILE_PROVIDED = $true; $i += 2
        }
        '^(-g|--global)$'     { $script:SCOPE = "global"; $i++ }
        '^--skills-only$'     { $script:INSTALL_MCP = $false; $script:SKILLS_ONLY = $true; $i++ }
        '^--mcp-only$'        { $script:INSTALL_SKILLS = $false; $i++ }
        '^--silent$'          { $script:SILENT = $true; $i++ }
        '^(-f|--force)$'      { $script:FORCE = $true; $i++ }
        '^(-h|--help)$' {
            Write-Host ""
            Write-Host "$ENTERPRISE_DISPLAY Enterprise AI Dev Kit Installer"
            Write-Host ""
            Write-Host "Usage: .\enterprise_install.ps1 [OPTIONS]"
            Write-Host ""
            Write-Host "Options:"
            Write-Host "  -p, --profile NAME     Databricks profile (default: DEFAULT)"
            Write-Host "  -g, --global           Install globally (not per-project)"
            Write-Host "  --skills-only          Fast path: only update skills (Steps 2 + 5 only)"
            Write-Host "  --mcp-only             Skip skills installation"
            Write-Host "  --silent               No output except errors"
            Write-Host "  -f, --force            Force reinstall"
            Write-Host ""
            Write-Host "Environment variables:"
            Write-Host "  DEVKIT_PROFILE         Databricks config profile"
            Write-Host "  DEVKIT_FORCE           Set to 'true' to force reinstall"
            Write-Host "  AIDEVKIT_HOME          Install dir (default: ~/.ai-dev-kit)"
            exit 0
        }
        default { Write-Host "Unknown option: $($args[$i]) (use --help for options)" -ForegroundColor Red; exit 1 }
    }
}

# =============================================================================
# -- OUTPUT HELPERS ------------------------------------------------------------
# =============================================================================

function Write-Msg  { param([string]$Text) if (-not $script:SILENT) { Write-Host "  $Text" } }
function Write-Ok   {
    param([string]$Text)
    if (-not $script:SILENT) {
        Write-Host "  " -NoNewline
        Write-Host "v" -ForegroundColor Green -NoNewline
        Write-Host " $Text"
    }
}
function Write-Warn {
    param([string]$Text)
    if (-not $script:SILENT) {
        Write-Host "  " -NoNewline
        Write-Host "!" -ForegroundColor Yellow -NoNewline
        Write-Host " $Text"
    }
}
function Write-Die {
    param([string]$Text)
    Write-Host "  " -NoNewline
    Write-Host "x" -ForegroundColor Red -NoNewline
    Write-Host " $Text"
    Write-Host ""
    exit 1
}
function Write-Step {
    param([string]$Text)
    if (-not $script:SILENT) {
        Write-Host ""
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "  $Text" -ForegroundColor White
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
    }
}

function Get-DbxUser {
    param([string]$Json)
    if ($Json -match '"userName"\s*:\s*"([^@"]+@[^"]+)"') { return $Matches[1] }
    if ($Json -match '"value"\s*:\s*"([^@"]+@[^"]+)"')    { return $Matches[1] }
    if ($Json -match '"userName"\s*:\s*"([^"]+)"')         { return $Matches[1] }
    return ""
}

function Test-VersionGte {
    param([string]$Have, [string]$Need)
    try {
        return ([version]$Have) -ge ([version]$Need)
    } catch {
        return $false
    }
}

# =============================================================================
# -- INTERACTIVE HELPERS -------------------------------------------------------
# =============================================================================

function Test-Interactive {
    if ($script:SILENT) { return $false }
    try { $host.UI.RawUI.KeyAvailable | Out-Null; return $true } catch { return $false }
}

function Read-Prompt {
    param([string]$PromptText, [string]$Default = "")
    if ($script:SILENT) { return $Default }
    if (Test-Interactive) {
        Write-Host "  $PromptText [$Default]: " -NoNewline
        $result = Read-Host
        if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
        return $result
    }
    return $Default
}

# Arrow-key radio selector
function Select-Radio {
    param([string]$Title, [array]$Items)

    $count    = $Items.Count
    $cursor   = 0
    $selected = 0

    $isInteractive = Test-Interactive

    if (-not $isInteractive) {
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor White
        for ($j = 0; $j -lt $count; $j++) {
            Write-Host "    $($j + 1)) $($Items[$j].Label)  $($Items[$j].Hint)"
        }
        Write-Host ""
        Write-Host "  Enter number [1]: " -NoNewline
        $choice = Read-Host
        $idx = if ([string]::IsNullOrWhiteSpace($choice)) { 0 } else { [int]$choice - 1 }
        if ($idx -lt 0 -or $idx -ge $count) { $idx = 0 }
        return $Items[$idx].Value
    }

    $totalRows = $count + 2

    try { [Console]::CursorVisible = $false } catch {}

    $drawRadio = {
        $winW = [Console]::WindowWidth
        [Console]::SetCursorPosition(0, [Math]::Max(0, [Console]::CursorTop - $totalRows))
        for ($j = 0; $j -lt $count; $j++) {
            $hint    = $Items[$j].Hint
            $maxHint = $winW - 35
            if ($maxHint -lt 0) { $maxHint = 0 }
            if ($hint.Length -gt $maxHint) { $hint = $hint.Substring(0, [Math]::Max(0, $maxHint - 3)) + "..." }

            if ($j -eq $cursor) {
                Write-Host "  " -NoNewline
                Write-Host ">" -ForegroundColor Cyan -NoNewline
                Write-Host " " -NoNewline
            } else {
                Write-Host "    " -NoNewline
            }
            if ($j -eq $selected) {
                Write-Host "(*)" -ForegroundColor Green -NoNewline
            } else {
                Write-Host "( )" -ForegroundColor DarkGray -NoNewline
            }
            $padLabel = $Items[$j].Label.PadRight(24)
            Write-Host " $padLabel " -NoNewline
            if ($j -eq $selected) {
                Write-Host $hint -ForegroundColor Green -NoNewline
            } else {
                Write-Host $hint -ForegroundColor DarkGray -NoNewline
            }
            $pos       = [Console]::CursorLeft
            $remaining = $winW - $pos - 1
            if ($remaining -gt 0) { Write-Host (' ' * $remaining) -NoNewline }
            Write-Host ""
        }
        Write-Host (' ' * ($winW - 1))
        if ($cursor -eq $count) {
            Write-Host "  " -NoNewline
            Write-Host ">" -ForegroundColor Cyan -NoNewline
            Write-Host " " -NoNewline
            Write-Host "[ Confirm ]" -ForegroundColor Green -NoNewline
        } else {
            Write-Host "    " -NoNewline
            Write-Host "[ Confirm ]" -ForegroundColor DarkGray -NoNewline
        }
        $pos       = [Console]::CursorLeft
        $remaining = [Console]::WindowWidth - $pos - 1
        if ($remaining -gt 0) { Write-Host (' ' * $remaining) -NoNewline }
        Write-Host ""
    }

    Write-Host ""
    Write-Host "  $Title" -ForegroundColor White
    Write-Host "  Up/Down navigate | Enter confirm" -ForegroundColor DarkGray
    Write-Host ""
    for ($j = 0; $j -lt $totalRows; $j++) { Write-Host "" }
    & $drawRadio

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            38 { if ($cursor -gt 0) { $cursor-- }; if ($cursor -lt $count) { $selected = $cursor } }
            40 { if ($cursor -lt $count) { $cursor++ }; if ($cursor -lt $count) { $selected = $cursor } }
            13 { if ($cursor -lt $count) { $selected = $cursor }; & $drawRadio; break }
        }
        if ($key.VirtualKeyCode -eq 13) { break }
        & $drawRadio
    }

    try { [Console]::CursorVisible = $true } catch {}
    return $Items[$selected].Value
}

# =============================================================================
# -- BANNER -------------------------------------------------------------------
# =============================================================================

Write-Host ""
$_bannerTitle = "   $ENTERPRISE_DISPLAY - Enterprise AI Dev Kit Installer"
$_inner       = [Math]::Max(56, $_bannerTitle.Length + 2)
$_border      = '=' * $_inner
$_pad         = $_inner - $_bannerTitle.Length
$_padded      = $_bannerTitle + (' ' * $_pad)
Write-Host "+${_border}+" -ForegroundColor Cyan
Write-Host "|" -ForegroundColor Cyan -NoNewline
Write-Host $_padded -NoNewline
Write-Host "|" -ForegroundColor Cyan
Write-Host "+${_border}+" -ForegroundColor Cyan
Write-Host ""
Write-Warn "NOTE: Do NOT run the official Databricks install.ps1 alongside this script."
Write-Msg  "  This enterprise installer fully replaces it. Running both will break the MCP config."
Write-Host ""

# =============================================================================
# -- REPO SETUP ----------------------------------------------------------------
# =============================================================================

if ($_LOCAL_REPO_MODE) {
    Write-Ok "Using local repo  ->  $REPO_DIR"
} else {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "  x git not found - run prerequisites first:" -ForegroundColor Red
        Write-Host "    irm ${_raw_base}/${ENTERPRISE_KIT_BRANCH}/prerequisites.ps1 | iex"
        Write-Host ""
        exit 1
    }
    Write-Msg "Checking enterprise kit repo..."
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $env:GIT_HTTP_LOW_SPEED_LIMIT = "1000"; $env:GIT_HTTP_LOW_SPEED_TIME = "30"
    if (Test-Path (Join-Path $REPO_DIR ".git")) {
        & git -C $REPO_DIR fetch -q --depth 1 origin $ENTERPRISE_KIT_BRANCH 2>&1 | Out-Null
        & git -C $REPO_DIR reset --hard FETCH_HEAD 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "Enterprise kit updated  ->  $REPO_DIR" }
        else                      { Write-Warn "Could not update enterprise kit — using existing version" }
    } else {
        if (-not (Test-Path $INSTALL_DIR)) { New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null }
        & git clone -q --depth 1 --branch $ENTERPRISE_KIT_BRANCH $ENTERPRISE_KIT_REPO $REPO_DIR 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "Enterprise kit ready  ->  $REPO_DIR" }
        else {
            $ErrorActionPreference = $prevEAP
            Remove-Item Env:\GIT_HTTP_LOW_SPEED_LIMIT, Env:\GIT_HTTP_LOW_SPEED_TIME -ErrorAction SilentlyContinue
            Write-Die "Failed to clone enterprise kit from: $ENTERPRISE_KIT_REPO"
        }
    }
    Remove-Item Env:\GIT_HTTP_LOW_SPEED_LIMIT, Env:\GIT_HTTP_LOW_SPEED_TIME -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
}
Write-Host ""

# =============================================================================
# -- STEP 1: PROJECT DIRECTORY -------------------------------------------------
# =============================================================================

if ($script:SKILLS_ONLY) {
    $script:PROJECT_DIR = (Get-Location).Path
    Write-Ok "Project dir: $($script:PROJECT_DIR)"
} else {
    Write-Step "Step 1 of 6 - Project Directory"
    $script:PROJECT_DIR = Read-Prompt "Project directory" (Get-Location).Path
    if (-not (Test-Path $script:PROJECT_DIR)) {
        New-Item -ItemType Directory -Path $script:PROJECT_DIR -Force | Out-Null
    }
    $script:PROJECT_DIR = (Resolve-Path $script:PROJECT_DIR).Path
    Write-Ok "Project dir: $($script:PROJECT_DIR)"
}

$_skillsDir = Join-Path $script:PROJECT_DIR ".claude\skills"
if (-not (Test-Path $_skillsDir)) { New-Item -ItemType Directory -Path $_skillsDir -Force | Out-Null }
Write-Ok "Workspace directories created"

# =============================================================================
# -- STEP 2: PREREQUISITES -----------------------------------------------------
# =============================================================================

Write-Step "Step 2 of 6 - Prerequisites"

$_PREREQ_SCRIPT = "${_raw_base}/${ENTERPRISE_KIT_BRANCH}/prerequisites.ps1"

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVer = (& git --version 2>&1)
    Write-Ok "$gitVer"
} else {
    Write-Die "git not found. Run prerequisites first:  irm $_PREREQ_SCRIPT | iex"
}

if (-not $script:SKILLS_ONLY) {

    if (Get-Command uv -ErrorAction SilentlyContinue) {
        $uvVer = [string](& uv --version 2>$null | Select-Object -First 1)
        Write-Ok "uv $uvVer"
    } else {
        Write-Die "uv not found. Run prerequisites first:  irm $_PREREQ_SCRIPT | iex"
    }

    # -- Databricks CLI --------------------------------------------------------
    if (Get-Command databricks -ErrorAction SilentlyContinue) {
        $cliVer = [string](& databricks --version 2>$null | Select-Object -First 1)
        Write-Ok "Databricks CLI: $cliVer"
    } else {
        Write-Warn "Databricks CLI not found — installing..."
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            & winget install Databricks.DatabricksCLI --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
            & choco install databricks-cli -y 2>&1 | Out-Null
        } else {
            Write-Warn "No package manager found — install Databricks CLI manually:"
            Write-Msg  "  https://docs.databricks.com/dev-tools/cli/install.html"
        }
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        if (Get-Command databricks -ErrorAction SilentlyContinue) {
            Write-Ok "Databricks CLI: $([string](& databricks --version 2>$null | Select-Object -First 1)) (just installed)"
        } else {
            Write-Warn "Databricks CLI install may have failed — install manually and re-run"
        }
        $ErrorActionPreference = $prevEAP
    }

} # end SKILLS_ONLY skip

# =============================================================================
# -- STEP 3: DATABRICKS WORKSPACE & PROFILE ------------------------------------
# =============================================================================

if (-not $script:SKILLS_ONLY) {

Write-Step "Step 3 of 6 - Databricks Workspace & Profile"

# -- Read existing profiles from ~/.databrickscfg -----------------------------
$dbxCfg       = Join-Path $env:USERPROFILE ".databrickscfg"
$knownProfiles = @()

if (Test-Path $dbxCfg) {
    foreach ($line in (Get-Content $dbxCfg)) {
        if ($line -match '^\[([a-zA-Z0-9_-]+)\]$') {
            $knownProfiles += $Matches[1]
        }
    }
}

# -- Profile selection --------------------------------------------------------
if (-not $script:PROFILE_PROVIDED -and -not $script:SILENT) {
    Write-Host ""
    if ($knownProfiles.Count -gt 0) {
        $pItems = @()
        foreach ($p in $knownProfiles) {
            $hint = if ($p -eq "DEFAULT") { "default" } else { "" }
            $pItems += @{ Label = $p; Value = $p; Hint = $hint }
        }
        $pItems += @{ Label = "Create new profile..."; Value = "__NEW__"; Hint = "enter workspace URL and profile name" }

        $selectedProfile = Select-Radio -Title "Choose Databricks profile:" -Items $pItems
        if ($selectedProfile -eq "__NEW__") {
            $script:WORKSPACE_URL = Read-Prompt "Databricks workspace URL" "https://"
            $script:WORKSPACE_URL = $script:WORKSPACE_URL.TrimEnd('/')
            $script:PROFILE_      = Read-Prompt "Profile name" "DEFAULT"
        } else {
            $script:PROFILE_ = $selectedProfile
            Write-Ok "Profile: $($script:PROFILE_)"
        }
    } else {
        Write-Msg "No ~/.databrickscfg found."
        $script:WORKSPACE_URL = Read-Prompt "Databricks workspace URL" "https://"
        $script:WORKSPACE_URL = $script:WORKSPACE_URL.TrimEnd('/')
        $script:PROFILE_      = Read-Prompt "Profile name" "DEFAULT"
    }
}

# -- Derive workspace URL from existing profile if not set --------------------
if ([string]::IsNullOrEmpty($script:WORKSPACE_URL) -and (Test-Path $dbxCfg)) {
    $inProfile = $false
    foreach ($line in (Get-Content $dbxCfg)) {
        if ($line -match "^\[$([regex]::Escape($script:PROFILE_))\]$") {
            $inProfile = $true
        } elseif ($line -match '^\[') {
            $inProfile = $false
        } elseif ($inProfile -and $line -match '^host\s*=\s*(.+)$') {
            $script:WORKSPACE_URL = $Matches[1].Trim().TrimEnd('/')
            break
        }
    }
}

# -- Authenticate if needed ---------------------------------------------------
Write-Host ""
$prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
if (Get-Command databricks -ErrorAction SilentlyContinue) {
    $authJson = (& databricks current-user me --profile $script:PROFILE_ --output json 2>&1)
    $authUser = Get-DbxUser "$authJson"
    if ($authUser) {
        Write-Ok "Already authenticated as $authUser"
        if ([string]::IsNullOrEmpty($script:WORKSPACE_URL)) {
            Write-Warn "Could not determine workspace URL from profile — you can set it manually later"
        } else {
            Write-Ok "Workspace: $($script:WORKSPACE_URL)"
        }
    } else {
        if ([string]::IsNullOrEmpty($script:WORKSPACE_URL)) {
            $script:WORKSPACE_URL = Read-Prompt "Databricks workspace URL" "https://"
            $script:WORKSPACE_URL = $script:WORKSPACE_URL.TrimEnd('/')
        }
        Write-Warn "Not authenticated — opening browser for OAuth login..."
        & databricks auth login --host $script:WORKSPACE_URL --profile $script:PROFILE_
        $authJson2 = (& databricks current-user me --profile $script:PROFILE_ --output json 2>&1)
        $authUser2 = Get-DbxUser "$authJson2"
        if ($authUser2) { Write-Ok "Authenticated as $authUser2" }
    }
}
$ErrorActionPreference = $prevEAP

} # end SKILLS_ONLY skip

# =============================================================================
# -- STEP 4: DATABRICKS MCP ---------------------------------------------------
# =============================================================================

if ($script:INSTALL_MCP) {
    Write-Step "Step 4 of 6 - Databricks MCP"
    Write-Msg "Setting up Databricks MCP server..."

    if (-not (Test-Path (Join-Path $REPO_DIR "databricks-mcp-server"))) {
        Write-Die "databricks-mcp-server not found in $REPO_DIR"
    }

    # Check if MCP server is currently running
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $mcpRunning = Get-Process -Name "python*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -like "*$INSTALL_DIR*" }
    $ErrorActionPreference = $prevEAP
    if ($mcpRunning) {
        Write-Warn "MCP server is currently running (Claude Code is open)."
        Write-Msg  "  Packages will update but new version takes effect after restarting Claude Code."
        Write-Host ""
    }

    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    if (-not (Test-Path $VENV_DIR)) { New-Item -ItemType Directory -Path $VENV_DIR -Force | Out-Null }
    & uv venv --python 3.11 --allow-existing $VENV_DIR -q 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { & uv venv --allow-existing $VENV_DIR -q 2>&1 | Out-Null }

    Write-Msg "Installing Python dependencies..."
    & uv pip install --python $VENV_PYTHON --native-tls `
        -e "$REPO_DIR\databricks-tools-core" `
        -e "$REPO_DIR\databricks-mcp-server" --quiet 2>&1 | Out-Null

    & $VENV_PYTHON -c "import databricks_mcp_server" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $ErrorActionPreference = $prevEAP
        Write-Die "MCP server import failed after install."
    }
    $ErrorActionPreference = $prevEAP
    Write-Ok "MCP server ready  ->  $VENV_DIR"

    # -- Write .mcp.json -------------------------------------------------------
    $MCP_CONFIG    = Join-Path $script:PROJECT_DIR ".mcp.json"
    $mcpVenvPython = $VENV_PYTHON -replace '\\', '/'
    $mcpEntry      = $MCP_ENTRY   -replace '\\', '/'
    $mcpConfigFwd  = $MCP_CONFIG  -replace '\\', '/'

    $mcpScript = @"
import json, pathlib
path = pathlib.Path('$mcpConfigFwd')
existing = {}
if path.exists():
    try: existing = json.loads(path.read_text())
    except: pass
existing.setdefault('mcpServers', {})['databricks'] = {
    'command': '$mcpVenvPython',
    'args':    ['$mcpEntry'],
    'defer_loading': True,
    'env': {'DATABRICKS_CONFIG_PROFILE': '$($script:PROFILE_)'}
}
path.write_text(json.dumps(existing, indent=2) + '\n')
"@
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    & $VENV_PYTHON -c $mcpScript 2>&1 | Out-Null
    $mcpWriteOk = $?
    $ErrorActionPreference = $prevEAP
    if ($mcpWriteOk) { Write-Ok "Databricks MCP  ->  $MCP_CONFIG" }
    else             { Write-Warn "Failed to write Databricks MCP entry — check .mcp.json for JSON errors" }
}

$MCP_CONFIG = Join-Path $script:PROJECT_DIR ".mcp.json"

# =============================================================================
# -- STEP 5: SKILLS + SETTINGS ------------------------------------------------
# =============================================================================

Write-Step "Step 5 of 6 - Skills + Settings"

# -- Write .claude/settings.json -----------------------------------------------
$SETTINGS_PATH  = Join-Path $script:PROJECT_DIR ".claude\settings.json"
$settingsScript = @"
import json, pathlib
path = pathlib.Path(r'$($SETTINGS_PATH -replace "'","\\'")')
path.parent.mkdir(parents=True, exist_ok=True)
existing = {}
if path.exists():
    try: existing = json.loads(path.read_text())
    except: pass
hook_cmd = r'$($UPDATE_CHECK_CMD -replace "'","\\'")'
hooks = existing.setdefault('hooks', {})
session = hooks.setdefault('SessionStart', [])
if not any('check_update' in str(h) for g in session for h in g.get('hooks', [])):
    session.append({'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 5}]})
path.write_text(json.dumps(existing, indent=2) + '\n')
"@

$settingsOk = $false
$prevEAP    = $ErrorActionPreference; $ErrorActionPreference = "Continue"
if (Test-Path $VENV_PYTHON) {
    & $VENV_PYTHON -c $settingsScript 2>&1 | Out-Null
    if ($?) { $settingsOk = $true }
}
if (-not $settingsOk -and (Get-Command python -ErrorAction SilentlyContinue)) {
    & python -c $settingsScript 2>&1 | Out-Null
    if ($?) { $settingsOk = $true }
}
if (-not $settingsOk -and (Get-Command python3 -ErrorAction SilentlyContinue)) {
    & python3 -c $settingsScript 2>&1 | Out-Null
    if ($?) { $settingsOk = $true }
}
$ErrorActionPreference = $prevEAP
if ($settingsOk) { Write-Ok ".claude/settings.json  ->  $SETTINGS_PATH" }
else             { Write-Warn "Could not write settings.json — Python not found. Install Python and re-run." }

# -- Install skills ------------------------------------------------------------
if ($script:INSTALL_SKILLS) {
    Write-Host ""
    Write-Msg "Installing skills..."
    $SKILLS_DEST = Join-Path $script:PROJECT_DIR ".claude\skills"
    if (-not (Test-Path $SKILLS_DEST)) { New-Item -ItemType Directory -Path $SKILLS_DEST -Force | Out-Null }

    $_adk = Join-Path $script:PROJECT_DIR ".ai-dev-kit"
    if (-not (Test-Path $_adk)) { New-Item -ItemType Directory -Path $_adk -Force | Out-Null }
    Set-Content -Path (Join-Path $_adk ".installed-skills") -Value "" -NoNewline

    # -- MLflow skills from mlflow/skills repo ---------------------------------
    $MLFLOW_COUNT = 0
    Write-Msg "Fetching MLflow skills..."
    foreach ($skill in $MLFLOW_SKILLS) {
        $skillDest = Join-Path $SKILLS_DEST $skill
        if (-not (Test-Path $skillDest)) { New-Item -ItemType Directory -Path $skillDest -Force | Out-Null }
        $skillMd  = Join-Path $skillDest "SKILL.md"
        $skillUrl = "$MLFLOW_BASE_URL/$skill/SKILL.md"
        $prevEAP  = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        $ok = $false
        try {
            Invoke-WebRequest -Uri $skillUrl -OutFile $skillMd -UseBasicParsing -ErrorAction Stop
            foreach ($ref in @("reference.md", "examples.md", "api.md")) {
                try { Invoke-WebRequest -Uri "$MLFLOW_BASE_URL/$skill/$ref" -OutFile (Join-Path $skillDest $ref) -UseBasicParsing -ErrorAction Stop } catch {}
            }
            Add-Content -Path (Join-Path $_adk ".installed-skills") -Value "$SKILLS_DEST|$skill"
            $MLFLOW_COUNT++; $ok = $true
        } catch {}
        $ErrorActionPreference = $prevEAP
        if (-not $ok) {
            if (Test-Path $skillDest) { Remove-Item $skillDest -Recurse -Force }
            Write-Warn "Could not fetch MLflow skill: $skill (re-run with --skills-only once rate limit clears)"
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Ok "MLflow skills  ($MLFLOW_COUNT installed)"

    # -- Blackstraw enterprise skills bundled in this repo ---------------------
    $blkSkillCount = 0
    $blkSkillsSrc  = Join-Path $REPO_DIR ".claude\skills"
    if (Test-Path $blkSkillsSrc) {
        Get-ChildItem $blkSkillsSrc -Directory | Where-Object { $_.Name -like "blackstraw-*" } | ForEach-Object {
            $bName = $_.Name
            $bDest = Join-Path $SKILLS_DEST $bName
            if (Test-Path $bDest) { Remove-Item $bDest -Recurse -Force -ErrorAction SilentlyContinue }
            Copy-Item $_.FullName $bDest -Recurse -Force
            Add-Content -Path (Join-Path $_adk ".installed-skills") -Value "$SKILLS_DEST|$bName"
            $blkSkillCount++
        }
    }
    Write-Ok "Blackstraw skills  ($blkSkillCount installed)"

    # -- Agent skills via databricks aitools ------------------------------------
    # Follows the official ai-dev-kit flow exactly:
    #   1. Count expected skills from live inventory
    #   2. Ensure Claude plugin marketplace is registered (required before aitools runs)
    #   3. Run `databricks aitools install` (plugin install for Claude Code)
    #   4. Verify the plugin actually registered
    $AGENT_COUNT = 0
    $aitoolsOk   = $false
    $cliVer      = ""
    $prevEAP     = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    if (Get-Command databricks -ErrorAction SilentlyContinue) {
        $cliVer = (& databricks --version 2>&1) -join "" |
            Select-String -Pattern '[0-9]+\.[0-9]+\.[0-9]+' |
            ForEach-Object { $_.Matches[0].Value } | Select-Object -First 1
    }
    $ErrorActionPreference = $prevEAP
    if ($cliVer -and (Test-VersionGte $cliVer $MIN_AITOOLS_CLI_VERSION)) { $aitoolsOk = $true }

    if ($aitoolsOk) {
        # Ensure Claude Code plugin marketplace is registered before aitools runs.
        # Without this, `databricks aitools install --agents claude-code` silently
        # fails to install the plugin even though it exits 0.
        if (Get-Command claude -ErrorAction SilentlyContinue) {
            $mpName  = "claude-plugins-official"
            $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
            $mpPresent = (& claude plugin marketplace list 2>&1) -join "" | Select-String -Pattern $mpName
            if (-not $mpPresent) {
                Write-Msg "Registering Claude plugin marketplace..."
                try { & claude plugin marketplace add anthropics/claude-plugins-official 2>&1 | Out-Null }
                catch { Write-Warn "Could not register Claude marketplace — plugin install may fail" }
            } else {
                try { & claude plugin marketplace update $mpName 2>&1 | Out-Null } catch {}
            }
            $ErrorActionPreference = $prevEAP
        }

            # Install agent skills as a Claude Code plugin (+ experimental skills)
        $prevEAP    = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        $aitoolsOut = (& databricks aitools install --scope project --agents claude-code --experimental -p $script:PROFILE_ 2>&1) -join "`n"
        $aitoolsRc  = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP

        if ($aitoolsRc -eq 0) {
            # Count from the fallback list (mirrors official installer's _count approach).
            $AGENT_COUNT = ($AGENT_B_STABLE_FALLBACK + $AGENT_B_EXPERIMENTAL_FALLBACK).Count
            Write-Ok "Agent skills  ($AGENT_COUNT installed via databricks aitools)"
            # Verify the Claude plugin actually registered
            if (Get-Command claude -ErrorAction SilentlyContinue) {
                $prevEAP     = $ErrorActionPreference; $ErrorActionPreference = "Continue"
                $pluginCheck = (& claude plugin list --json 2>&1) -join "" | Select-String -Pattern "databricks@claude-plugins-official"
                if (-not $pluginCheck) {
                    $pluginCheck = (& claude plugin list 2>&1) -join "" | Select-String -Pattern "databricks@claude-plugins-official"
                }
                $ErrorActionPreference = $prevEAP
                if (-not $pluginCheck) {
                    Write-Warn "Claude plugin not confirmed — run manually if skills are missing:"
                    Write-Warn "  claude plugin install databricks@claude-plugins-official --scope project"
                }
            }
        } else {
            Write-Warn "databricks aitools install failed — agent skills not installed"
            if ($aitoolsOut -match "429|rate.limit") {
                Write-Warn "  Cause: GitHub rate limit — wait a minute and re-run with --skills-only"
            } else {
                Write-Warn "  Run manually: databricks aitools install --scope project --agents claude-code --experimental -p $($script:PROFILE_)"
            }
            $AGENT_COUNT = 0
        }
    } else {
        Write-Warn "Agent skills skipped — Databricks CLI v${MIN_AITOOLS_CLI_VERSION}+ required"
        if ($cliVer) { Write-Warn "  Found: v${cliVer}" } else { Write-Warn "  Databricks CLI not found" }
        Write-Warn "  Upgrade: winget install Databricks.DatabricksCLI"
        Write-Warn "  Then re-run: $_RERUN_CMD"
    }

    # -- Enterprise private skills repo ----------------------------------------
    $entSkillCount = 0
    if ($ENTERPRISE_SKILLS_REPO) {
        Write-Msg "Fetching enterprise skills from: $ENTERPRISE_SKILLS_REPO"

        # Try SSH; fall back to HTTPS
        $entCloneUrl = $ENTERPRISE_SKILLS_REPO
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        $sshCheck = (& ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1) -join ""
        $ErrorActionPreference = $prevEAP
        if ($sshCheck -notmatch "Hi ") {
            $entCloneUrl = $ENTERPRISE_SKILLS_REPO -replace '^git@github\.com:', 'https://github.com/'
            Write-Msg "SSH not available — using HTTPS: $entCloneUrl"
        }

        # Check reachability
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        & git ls-remote --exit-code $entCloneUrl HEAD 2>&1 | Out-Null
        $entReachable = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prevEAP

        if ($entReachable) {
            $repoGitDir = Join-Path $ENTERPRISE_SKILLS_REPO_DIR ".git"
            if (Test-Path $repoGitDir) {
                $curRemote = (& git -C $ENTERPRISE_SKILLS_REPO_DIR remote get-url origin 2>&1) -join ""
                if ($curRemote -ne $entCloneUrl) { Remove-Item $ENTERPRISE_SKILLS_REPO_DIR -Recurse -Force -ErrorAction SilentlyContinue }
            }

            $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
            if (Test-Path $repoGitDir) {
                & git -C $ENTERPRISE_SKILLS_REPO_DIR fetch -q --depth 1 origin HEAD 2>&1 | Out-Null
                & git -C $ENTERPRISE_SKILLS_REPO_DIR reset -q --hard FETCH_HEAD 2>&1 | Out-Null
            } else {
                & git clone -q --depth 1 $entCloneUrl $ENTERPRISE_SKILLS_REPO_DIR 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { $entReachable = $false; Write-Warn "Could not clone enterprise skills repo" }
            }
            $ErrorActionPreference = $prevEAP

            if ($entReachable) {
                $entSrc = $ENTERPRISE_SKILLS_REPO_DIR
                if ($ENTERPRISE_SKILLS_REPO_SUBPATH) { $entSrc = Join-Path $entSrc $ENTERPRISE_SKILLS_REPO_SUBPATH }

                if (Test-Path $entSrc) {
                    Get-ChildItem $entSrc -Directory | Where-Object { $_.Name -ne "TEMPLATE" } | ForEach-Object {
                        $eName = $_.Name
                        $eDest = Join-Path $SKILLS_DEST $eName
                        if (Test-Path $eDest) { Remove-Item $eDest -Recurse -Force -ErrorAction SilentlyContinue }
                        Copy-Item $_.FullName $eDest -Recurse -Force
                        Add-Content -Path (Join-Path $_adk ".installed-skills") -Value "$SKILLS_DEST|$eName"
                        $entSkillCount++
                    }
                    Write-Ok "Enterprise skills  ($entSkillCount installed)"
                } else {
                    Write-Warn "Enterprise skills subfolder not found: $entSrc"
                }
            }
        } else {
            Write-Warn "Enterprise skills repo not reachable — skipping"
            Write-Warn "  Repo: $ENTERPRISE_SKILLS_REPO"
            Write-Warn "  Configure later and re-run with --skills-only"
        }
    }

    # -- Genie sync (optional) -------------------------------------------------
    if (Get-Command databricks -ErrorAction SilentlyContinue) {
        $prevEAP    = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        $genieUser  = ""
        $genieAuth  = (& databricks current-user me --profile $script:PROFILE_ --output json 2>&1)
        $genieUser  = Get-DbxUser "$genieAuth"
        $ErrorActionPreference = $prevEAP

        if ($genieUser) {
            Write-Host ""
            $doGenie = Read-Prompt "Would you like to upload Skills to Genie Code? (y/n)" "y"
            if ($doGenie -in @("y","Y")) {
                $genieTarget  = "/Workspace/Users/$genieUser/.assistant/skills"
                $skillsLocal  = Join-Path $script:PROJECT_DIR ".claude\skills"
                Write-Host ""
                Write-Host "  " -NoNewline; Write-Host "Workspace user: " -NoNewline -ForegroundColor White; Write-Host $genieUser
                Write-Host "  " -NoNewline; Write-Host "Workspace path: " -NoNewline -ForegroundColor White; Write-Host $genieTarget
                Write-Host ""
                $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
                & databricks workspace mkdirs $genieTarget --profile $script:PROFILE_ 2>&1 | Out-Null
                $genieFail = 0
                Get-ChildItem $skillsLocal -Directory | ForEach-Object {
                    $skillName  = $_.Name
                    $skillLocal = $_.FullName
                    Write-Host "  " -NoNewline
                    Write-Host "Uploading " -NoNewline -ForegroundColor Cyan
                    Write-Host $skillName
                    & databricks workspace import-dir $skillLocal "$genieTarget/$skillName" --overwrite --profile $script:PROFILE_ 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { $genieFail++ }
                }
                $ErrorActionPreference = $prevEAP
                Write-Host ""
                if ($genieFail -eq 0) { Write-Ok "Skills synced to Databricks Genie  ->  $genieTarget" }
                else                  { Write-Warn "$genieFail skill(s) failed to sync — check manually at: $genieTarget" }
            }
        }
    }
}

# =============================================================================
# -- STEP 6: WORKSPACE + VERSION LOCK -----------------------------------------
# =============================================================================

if (-not $script:SKILLS_ONLY) {

Write-Step "Step 6 of 6 - Workspace"

$_adk = Join-Path $script:PROJECT_DIR ".ai-dev-kit"
if (-not (Test-Path $_adk)) { New-Item -ItemType Directory -Path $_adk -Force | Out-Null }

$_adk_ver = "enterprise"
$verFile  = Join-Path $REPO_DIR "VERSION"
if (Test-Path $verFile) { $_adk_ver = (Get-Content $verFile -Raw).Trim() }
Set-Content -Path (Join-Path $_adk "version") -Value $_adk_ver
Write-Ok ".ai-dev-kit/version  ($_adk_ver)"

$installedSkillsFile = Join-Path $_adk ".installed-skills"
if (-not (Test-Path $installedSkillsFile)) { New-Item -ItemType File -Path $installedSkillsFile -Force | Out-Null }
Write-Ok ".ai-dev-kit/.installed-skills"

Set-Content -Path (Join-Path $_adk ".skills-profile") -Value "enterprise"
Write-Ok ".ai-dev-kit/.skills-profile"

# -- .gitignore ----------------------------------------------------------------
$GITIGNORE = Join-Path $script:PROJECT_DIR ".gitignore"
if (-not (Test-Path $GITIGNORE)) { New-Item -ItemType File -Path $GITIGNORE -Force | Out-Null }
$gitignoreContent = Get-Content $GITIGNORE -Raw -ErrorAction SilentlyContinue
if (-not $gitignoreContent) { $gitignoreContent = "" }
foreach ($rule in @(".ai-dev-kit/", ".claude/", ".mcp.json", ".env", "__pycache__/", "*.pyc")) {
    if ($gitignoreContent -notmatch [regex]::Escape($rule)) {
        Add-Content -Path $GITIGNORE -Value $rule
    }
}
Write-Ok ".gitignore updated"

} # end SKILLS_ONLY skip

# =============================================================================
# -- SUMMARY -------------------------------------------------------------------
# =============================================================================

Write-Host ""
if ($script:SKILLS_ONLY) {
    Write-Host "+========================================================+" -ForegroundColor Green
    Write-Host "|   v  Skills Updated                                    |" -ForegroundColor Green
    Write-Host "+========================================================+" -ForegroundColor Green
    Write-Host ""
    Write-Host ("  {0,-20} {1}" -f "Project",           $script:PROJECT_DIR)
    Write-Host ("  {0,-20} {1}" -f "MLflow skills",     "$MLFLOW_COUNT installed")
    Write-Host ("  {0,-20} {1}" -f "Agent skills",      "$AGENT_COUNT installed")
    Write-Host ("  {0,-20} {1}" -f "Blackstraw skills", "$blkSkillCount installed")
    if ($entSkillCount -gt 0) { Write-Host ("  {0,-20} {1}" -f "Enterprise skills", "$entSkillCount installed") }
} else {
    Write-Host "+========================================================+" -ForegroundColor Green
    Write-Host "|   v  Workspace Ready                                   |" -ForegroundColor Green
    Write-Host "+========================================================+" -ForegroundColor Green
    Write-Host ""
    Write-Host ("  {0,-20} {1}" -f "Project",           $script:PROJECT_DIR)
    Write-Host ("  {0,-20} {1}" -f "Enterprise",        $ENTERPRISE_DISPLAY)
    Write-Host ("  {0,-20} {1}" -f "Workspace",         $script:WORKSPACE_URL)
    Write-Host ("  {0,-20} {1}" -f "Profile",           $script:PROFILE_)
    Write-Host ("  {0,-20} {1}" -f "MLflow skills",     "$($MLFLOW_COUNT) installed")
    Write-Host ("  {0,-20} {1}" -f "Agent skills",      "$($AGENT_COUNT) installed")
    if ($entSkillCount -gt 0) { Write-Host ("  {0,-20} {1}" -f "Enterprise skills", "$entSkillCount installed") }
    Write-Host ("  {0,-20} {1}" -f "MCP config",        $MCP_CONFIG)
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open your project in Claude Code:  claude $($script:PROJECT_DIR)" -ForegroundColor Cyan
Write-Host "  2. MCP + skills are active — try: `"List my SQL warehouses`""
Write-Host ""
