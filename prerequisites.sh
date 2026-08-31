#!/usr/bin/env bash
#
# Blackstraw Enterprise Dev Environment — Prerequisites Installer (macOS / Linux)
#
# Checks and installs the following prerequisites:
#   1. Git  — with GitHub authentication and git identity config
#   2. uv   — Python package / project manager (astral.sh)
#
# Usage:
#   bash prerequisites.sh
#   bash <(curl -sL https://raw.githubusercontent.com/blackstraw-ai/ai-dev-kit/main/prerequisites.sh)
#

set -euo pipefail

# =============================================================================
# ── CONFIGURATION ─────────────────────────────────────────────────────────────
# =============================================================================

ENTERPRISE_NAME="Blackstraw"
ENTERPRISE_DISPLAY="Blackstraw"
# Default email hint shown when no git/GitHub email is detected.
# Change this to match your organisation's email domain.
ENTERPRISE_DEFAULT_EMAIL="${ENTERPRISE_DEFAULT_EMAIL:-you@blackstraw.ai}"

# =============================================================================
# ── OUTPUT HELPERS ────────────────────────────────────────────────────────────
# =============================================================================

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[1m'; CY='\033[0;36m'; N='\033[0m'

msg()  { echo -e "  $*"; }
ok()   { echo -e "  ${G}✓${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
die()  { echo -e "  ${R}✗${N} $*" >&2; exit 1; }
step() { echo -e "\n${CY}────────────────────────────────────────────────────────${N}\n  ${B}$*${N}\n${CY}────────────────────────────────────────────────────────${N}\n"; }

prompt() {
    local text="$1" default="${2:-}" result=""
    printf "  %b [%s]: " "$text" "$default" > /dev/tty
    read -r result < /dev/tty
    [ -z "$result" ] && echo "$default" || echo "$result"
}

# =============================================================================
# ── BANNER ────────────────────────────────────────────────────────────────────
# =============================================================================

echo ""
_banner_title="   ${ENTERPRISE_DISPLAY} — Prerequisites Installer"
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

# =============================================================================
# ── PLATFORM CHECK ────────────────────────────────────────────────────────────
# =============================================================================

OS="$(uname -s)"
if [ "$OS" != "Darwin" ] && [ "$OS" != "Linux" ]; then
    die "Unsupported OS: $OS. This script supports macOS and Linux only."
fi

# =============================================================================
# ── HOMEBREW (macOS only) ─────────────────────────────────────────────────────
# =============================================================================

_ensure_brew() {
    if ! command -v brew >/dev/null 2>&1; then
        msg "Homebrew not found — installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
        if [ -f "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -f "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        ok "Homebrew installed"
    fi
}

# =============================================================================
# ── STEP 1: GIT ───────────────────────────────────────────────────────────────
# =============================================================================

step "Step 1 of 2 — Git"

if command -v git >/dev/null 2>&1; then
    ok "Git already installed  ($(git --version))"
else
    msg "Git not found — installing..."
    if [ "$OS" = "Darwin" ]; then
        _ensure_brew
        brew install git
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y git
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y git
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y git
    else
        die "Cannot install Git automatically. Install from: https://git-scm.com/download/linux"
    fi

    if command -v git >/dev/null 2>&1; then
        ok "Git installed  ($(git --version))"
    else
        die "Git installation failed. Install manually: https://git-scm.com"
    fi
fi

# -- GitHub CLI (gh) -----------------------------------------------------------

if command -v gh >/dev/null 2>&1; then
    ok "GitHub CLI already installed  ($(gh --version | head -1))"
else
    msg "GitHub CLI (gh) not found — installing..."
    if [ "$OS" = "Darwin" ]; then
        _ensure_brew
        brew install gh
    elif command -v apt-get >/dev/null 2>&1; then
        # Official gh apt repository
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update -qq && sudo apt-get install -y gh
    elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
        sudo install -m 0755 -d /etc/yum.repos.d 2>/dev/null || true
        sudo tee /etc/yum.repos.d/gh-cli.repo > /dev/null <<'REPO'
[gh-cli]
name=packages for the GitHub CLI
baseurl=https://cli.github.com/packages/rpm
enabled=1
gpgcheck=1
gpgkey=https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x23F3D4EA75716059
REPO
        if command -v dnf >/dev/null 2>&1; then sudo dnf install -y gh; else sudo yum install -y gh; fi
    else
        warn "Could not install gh CLI automatically — install manually: https://cli.github.com"
    fi

    if command -v gh >/dev/null 2>&1; then
        ok "GitHub CLI installed  ($(gh --version | head -1))"
    else
        warn "GitHub CLI not found after install — some features may not work"
    fi
fi

# -- Git identity ---------------------------------------------------------------

_configure_git_identity() {
    local current_name current_email default_name default_email name email

    current_name="$(git config --global user.name 2>/dev/null || true)"
    current_email="$(git config --global user.email 2>/dev/null || true)"

    # Try to pre-populate from gh profile
    if command -v gh >/dev/null 2>&1; then
        [ -z "$current_name" ]  && current_name="$(gh api user --jq '.name'  2>/dev/null || true)"
        [ -z "$current_email" ] && current_email="$(gh api user --jq '.email' 2>/dev/null || true)"
    fi

    default_name="${current_name:-First Last}"
    default_email="${current_email:-$ENTERPRISE_DEFAULT_EMAIL}"

    name=$(prompt  "Full name for git config" "$default_name")
    email=$(prompt "${ENTERPRISE_DISPLAY} email for git config" "$default_email")

    git config --global user.name          "$name"
    git config --global user.email         "$email"
    git config --global push.default       current
    git config --global pull.rebase        true
    git config --global init.defaultBranch main
    git config --global core.autocrlf      input

    ok "Git identity configured  ($name <$email>)"
}

# -- Ensure github.com is in known_hosts ---------------------------------------

_ensure_github_known_host() {
    local known_hosts="$HOME/.ssh/known_hosts"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

    if [ -f "$known_hosts" ] && grep -q "^github\.com" "$known_hosts" 2>/dev/null; then
        return
    fi

    local scan_out
    scan_out="$(ssh-keyscan -t ed25519 github.com 2>/dev/null || true)"
    if [ -n "$scan_out" ]; then
        echo "$scan_out" >> "$known_hosts"
    else
        # Hardcoded fallback — GitHub's published ed25519 host key
        echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" >> "$known_hosts"
    fi
    chmod 600 "$known_hosts"
    ok "GitHub SSH host key added to known_hosts"
}

# -- Main GitHub authentication flow -------------------------------------------

_authenticate_github() {
    _ensure_github_known_host

    local ssh_out
    ssh_out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 || true)"

    if echo "$ssh_out" | grep -q "Hi "; then
        local gh_user
        gh_user="$(echo "$ssh_out" | sed 's/Hi \([^!]*\)!.*/\1/')"
        ok "Already authenticated with GitHub  ($gh_user)"
        _configure_git_identity
        return
    fi

    msg "Not authenticated with GitHub — opening browser..."
    if command -v gh >/dev/null 2>&1; then
        gh auth login --web --git-protocol https 2>/dev/null || \
            gh auth login --git-protocol https
        gh auth setup-git 2>/dev/null || true
    else
        warn "gh CLI not available — configure git credentials manually"
    fi

    _configure_git_identity
}

_authenticate_github

# =============================================================================
# ── STEP 2: UV ────────────────────────────────────────────────────────────────
# =============================================================================

step "Step 2 of 2 — uv (Python package manager)"

if command -v uv >/dev/null 2>&1; then
    ok "uv already installed  ($(uv --version))"
else
    msg "uv not found — installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Add uv's bin dir to PATH for the remainder of this session
    for _uv_dir in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
        if [ -f "$_uv_dir/uv" ]; then
            export PATH="$_uv_dir:$PATH"
            break
        fi
    done

    if command -v uv >/dev/null 2>&1; then
        ok "uv installed  ($(uv --version))"
    else
        warn "uv installed but not in current PATH — restart your terminal or run:"
        msg "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
fi

# =============================================================================
# ── SUMMARY ───────────────────────────────────────────────────────────────────
# =============================================================================

echo ""
printf "${CY}%s${N}\n" "════════════════════════════════════════════════════════"
ok "Prerequisites installed successfully!"
printf "${CY}%s${N}\n" "════════════════════════════════════════════════════════"
echo ""
ok "Git  $(git --version 2>/dev/null || echo '(see above)')"
ok "uv   $(uv --version  2>/dev/null || echo 'restart terminal to activate')"
echo ""
msg "If uv is not found in a new terminal, add its bin dir to your shell profile:"
msg "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc  # or ~/.bashrc"
echo ""
msg "Next: run the enterprise installer"
msg "  bash enterprise_install.sh"
echo ""
