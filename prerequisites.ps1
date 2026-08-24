#Requires -Version 5.1
<#
.SYNOPSIS
    Blackstraw Enterprise Dev Environment - Prerequisites Installer (Windows)

.DESCRIPTION
    Checks and installs the following prerequisites:
      1. Git  - with GitHub authentication and git identity config
      2. uv   - Python package / project manager (astral.sh)

.USAGE
    powershell -ExecutionPolicy Bypass -File prerequisites.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Force TLS 1.2 — PowerShell 5.1 defaults to TLS 1.0/1.1 which modern servers
# reject. The SSL callback handles corporate proxy SSL inspection.
[System.Net.ServicePointManager]::SecurityProtocol                      = [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback   = { $true }

$script:scoopUpdated = $false

# =============================================================================
# -- CONFIGURATION ------------------------------------------------------------
# =============================================================================

$EnterpriseName    = "Blackstraw"
$EnterpriseDisplay = "Blackstraw"

# =============================================================================
# -- OUTPUT HELPERS -----------------------------------------------------------
# =============================================================================

function Write-Msg  { param([string]$Text) Write-Host "  $Text" }
function Write-Ok   { param([string]$Text) Write-Host "  " -NoNewline; Write-Host ([char]0x2713) -ForegroundColor Green  -NoNewline; Write-Host " $Text" }
function Write-Warn { param([string]$Text) Write-Host "  " -NoNewline; Write-Host "!"            -ForegroundColor Yellow -NoNewline; Write-Host " $Text" }
function Write-Die  { param([string]$Text) Write-Host "  " -NoNewline; Write-Host ([char]0x2717) -ForegroundColor Red    -NoNewline; Write-Host " $Text"; exit 1 }

function msg  { param([string]$Text) Write-Msg  $Text }
function ok   { param([string]$Text) Write-Ok   $Text }
function warn { param([string]$Text) Write-Warn $Text }
function die  { param([string]$Text) Write-Die  $Text }

function step {
    param([string]$Text)
    $line = "-" * 56
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor White
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function prompt_input {
    param([string]$Text, [string]$Default = "")
    $display = if ($Default) { "$Text [$Default]" } else { $Text }
    Write-Host "  ${display}: " -NoNewline
    $result = Read-Host
    if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
    return $result
}

function command_exists {
    param([string]$Cmd)
    return [bool](Get-Command $Cmd -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH    = "$machinePath;$userPath"
}

# Run a native command, capture stdout + stderr merged, return as string.
# Never throws on non-zero exit. Works on PS 5.1 and PS 7+.
function Invoke-Native {
    param([scriptblock]$Cmd)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & $Cmd 2>&1
        return ($out | ForEach-Object { "$_" }) -join "`n"
    } finally {
        $ErrorActionPreference = $prev
    }
}

# Download a file using curl.exe (primary, handles corporate proxies via WinHTTP)
# with Invoke-WebRequest as fallback.
function Invoke-Download {
    param([string]$Url, [string]$OutFile)
    $downloaded = $false

    if (command_exists "curl.exe") {
        $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        curl.exe -L --ssl-no-revoke -s -o $OutFile $Url 2>&1 | Out-Null
        $curlExit = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($curlExit -eq 0 -and (Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 0) {
            $downloaded = $true
        } elseif (Test-Path $OutFile) {
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $downloaded) {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
}

# =============================================================================
# -- SCOOP (package manager) --------------------------------------------------
# =============================================================================

function Ensure-Scoop {
    if (-not (command_exists "scoop")) {
        msg "Scoop not found — installing..."
        try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue } catch {}
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        Refresh-Path
        if (-not (command_exists "scoop")) {
            die "Scoop installation failed. Install manually: https://scoop.sh"
        }
        ok "Scoop installed"
    }

    if (-not $script:scoopUpdated) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        scoop update 2>&1 | Out-Null
        $ErrorActionPreference = $prev
        $script:scoopUpdated = $true
    }
}

# =============================================================================
# -- BANNER -------------------------------------------------------------------
# =============================================================================

Write-Host ""
$_bannerInner = 56
$_bannerTitle = "   $EnterpriseDisplay - Prerequisites Installer"
if ($_bannerTitle.Length -gt $_bannerInner) { $_bannerInner = $_bannerTitle.Length + 2 }
Write-Host ("+" + ("=" * $_bannerInner) + "+") -ForegroundColor Cyan
Write-Host ("|" + $_bannerTitle.PadRight($_bannerInner) + "|") -ForegroundColor Cyan
Write-Host ("+" + ("=" * $_bannerInner) + "+") -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# -- STEP 1: GIT --------------------------------------------------------------
# =============================================================================

step "Step 1 of 2 - Git"

function Install-GitFromZip {
    msg "Installing Git via MinGit ZIP extraction (no admin required)..."
    $gitDir = "$env:USERPROFILE\AppData\Local\Programs\git"
    $tmpZip = "$env:TEMP\mingit.zip"
    $tmpDir = "$env:TEMP\mingit_extract"

    $downloadUrl = $null
    try {
        $release     = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $asset       = $release.assets | Where-Object { $_.name -like "MinGit-*-64-bit.zip" } | Select-Object -First 1
        $downloadUrl = $asset.browser_download_url
        msg "Latest MinGit release: $($release.tag_name)"
    } catch {
        $downloadUrl = "https://github.com/git-for-windows/git/releases/download/v2.49.0.windows.1/MinGit-2.49.0-64-bit.zip"
        msg "Could not query GitHub API — using fallback MinGit version"
    }

    msg "Downloading MinGit..."
    Invoke-Download -Url $downloadUrl -OutFile $tmpZip

    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    if (Test-Path $gitDir) { Remove-Item $gitDir -Recurse -Force }

    New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

    $gitExe = Get-ChildItem -Path $tmpDir -Filter "git.exe" -Recurse |
        Where-Object { $_.DirectoryName -match "\\cmd$" } | Select-Object -First 1
    if (-not $gitExe) {
        $gitExe = Get-ChildItem -Path $tmpDir -Filter "git.exe" -Recurse | Select-Object -First 1
    }
    if (-not $gitExe) { die "git.exe not found in MinGit archive." }

    $gitRootDir = Split-Path $gitExe.DirectoryName -Parent
    Copy-Item -Path "$gitRootDir\*" -Destination $gitDir -Recurse -Force

    $gitCmdDir = Join-Path $gitDir "cmd"
    $gitBinDir = Join-Path $gitDir "bin"
    $userPath  = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $toAdd     = @($gitCmdDir, $gitBinDir) | Where-Object { $userPath -notlike "*$_*" }
    if ($toAdd) {
        [System.Environment]::SetEnvironmentVariable("PATH", ($toAdd -join ";") + ";$userPath", "User")
    }
    $env:PATH = "$gitCmdDir;$gitBinDir;" + $env:PATH

    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

if (command_exists "git") {
    ok "Git already installed  ($(git --version))"
} else {
    msg "Git not found — installing via Scoop..."
    Ensure-Scoop
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    scoop install git 2>&1 | Out-Null
    $ErrorActionPreference = $prev
    Refresh-Path

    if (-not (command_exists "git")) {
        warn "Scoop could not install Git (likely GPO restricts MSI installers)"
        msg "  Falling back to MinGit ZIP extraction..."
        Install-GitFromZip
    }

    if (command_exists "git") {
        ok "Git installed  ($(git --version))"
    } else {
        die "Git installation failed. Install manually: https://git-scm.com/download/win"
    }
}

# -- GitHub CLI (gh) ----------------------------------------------------------

function Install-GhFromZip {
    msg "Installing gh CLI via direct ZIP extraction (no admin required)..."
    $ghDir  = "$env:USERPROFILE\AppData\Local\Programs\gh"
    $tmpZip = "$env:TEMP\gh_windows_amd64.zip"
    $tmpDir = "$env:TEMP\gh_extract"

    $downloadUrl = $null
    try {
        $release     = Invoke-RestMethod -Uri "https://api.github.com/repos/cli/cli/releases/latest"
        $asset       = $release.assets | Where-Object { $_.name -like "*windows_amd64.zip" } | Select-Object -First 1
        $downloadUrl = $asset.browser_download_url
        msg "Latest gh release: $($release.tag_name)"
    } catch {
        $downloadUrl = "https://github.com/cli/cli/releases/download/v2.67.0/gh_2.67.0_windows_amd64.zip"
        msg "Could not query GitHub API — using fallback version"
    }

    msg "Downloading gh..."
    Invoke-Download -Url $downloadUrl -OutFile $tmpZip

    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    if (Test-Path $ghDir)  { Remove-Item $ghDir  -Recurse -Force }

    New-Item -ItemType Directory -Path $ghDir -Force | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

    $ghExe = Get-ChildItem -Path $tmpDir -Filter "gh.exe" -Recurse | Select-Object -First 1
    if (-not $ghExe) { die "gh.exe not found in downloaded archive." }
    Copy-Item -Path (Join-Path $ghExe.DirectoryName "*") -Destination $ghDir -Recurse -Force

    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$ghDir*") {
        [System.Environment]::SetEnvironmentVariable("PATH", "$ghDir;$userPath", "User")
    }
    $env:PATH = "$ghDir;" + $env:PATH

    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

if (command_exists "gh") {
    ok "GitHub CLI already installed  ($(gh --version | Select-Object -First 1))"
} else {
    msg "GitHub CLI (gh) not found — installing..."
    Ensure-Scoop
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    scoop install gh 2>&1 | Out-Null
    $ErrorActionPreference = $prev
    Refresh-Path

    if (-not (command_exists "gh")) {
        Install-GhFromZip
    }

    if (command_exists "gh") {
        ok "GitHub CLI installed  ($(gh --version | Select-Object -First 1))"
    } else {
        warn "GitHub CLI installation failed. Install manually: https://cli.github.com"
    }
}

# -- Git identity -------------------------------------------------------------

function Configure-GitIdentity {
    $currentName  = (Invoke-Native { git config --global user.name  }).Trim()
    $currentEmail = (Invoke-Native { git config --global user.email }).Trim()

    if (command_exists "gh") {
        if ([string]::IsNullOrWhiteSpace($currentName))  {
            $currentName  = (Invoke-Native { gh api user --jq '.name'  }).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($currentEmail)) {
            $currentEmail = (Invoke-Native { gh api user --jq '.email' }).Trim()
        }
    }

    $defaultName  = if ($currentName)  { $currentName }  else { "First Last" }
    $defaultEmail = if ($currentEmail) { $currentEmail } else { "you@blackstraw.ai" }

    $name  = prompt_input "Full name for git config" $defaultName
    $email = prompt_input "$EnterpriseDisplay email for git config" $defaultEmail

    git config --global user.name          $name
    git config --global user.email         $email
    git config --global push.default       current
    git config --global pull.rebase        true
    git config --global init.defaultBranch main
    git config --global core.autocrlf      true

    ok "Git identity configured  ($name <$email>)"
}

# -- Ensure github.com is in known_hosts --------------------------------------

function Ensure-GitHubKnownHost {
    $sshDir     = "$HOME\.ssh"
    $knownHosts = "$sshDir\known_hosts"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    if ((Test-Path $knownHosts) -and
        (Select-String -Path $knownHosts -Pattern "^github\.com" -Quiet -ErrorAction SilentlyContinue)) {
        return
    }

    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $scanOut = & ssh-keyscan -t ed25519 github.com 2>$null
    $ErrorActionPreference = $prev

    if ($scanOut -match "github\.com") {
        Add-Content -Path $knownHosts -Value ($scanOut -join "`n")
    } else {
        Add-Content -Path $knownHosts -Value "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
    }
    ok "GitHub SSH host key added to known_hosts"
}

# -- Main GitHub authentication flow ------------------------------------------

function Authenticate-GitHub {
    Ensure-GitHubKnownHost

    $prev    = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $sshOut  = Invoke-Native { ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com }
    $ErrorActionPreference = $prev

    if ($sshOut -match "Hi ([^!]+)!") {
        $ghUser = $Matches[1]
        ok "Already authenticated with GitHub  ($ghUser)"
        Configure-GitIdentity
        return
    }

    msg "Not authenticated with GitHub — opening browser..."
    if (command_exists "gh") {
        $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        & gh auth login --web --git-protocol https 2>&1 | Out-Null
        & gh auth setup-git 2>&1 | Out-Null
        $ErrorActionPreference = $prev
    } else {
        warn "gh CLI not available — configure git credentials manually"
    }

    Configure-GitIdentity
}

Authenticate-GitHub

# =============================================================================
# -- STEP 2: UV ---------------------------------------------------------------
# =============================================================================

step "Step 2 of 2 - uv (Python package manager)"

if (command_exists "uv") {
    ok "uv already installed  ($(uv --version))"
} else {
    msg "uv not found — installing..."
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    $ErrorActionPreference = $prev
    Refresh-Path

    # Probe common install locations
    foreach ($uvPath in @(
        "$env:USERPROFILE\.local\bin",
        "$env:USERPROFILE\.cargo\bin",
        "$env:APPDATA\uv\bin"
    )) {
        if (Test-Path "$uvPath\uv.exe") {
            $env:PATH = "$uvPath;" + $env:PATH
            break
        }
    }

    if (command_exists "uv") {
        ok "uv installed  ($(uv --version))"
    } else {
        warn "uv installed but not in current PATH. Restart your terminal or run:"
        msg '    $env:PATH = "$env:USERPROFILE\.local\bin;" + $env:PATH'
    }
}

# =============================================================================
# -- SUMMARY ------------------------------------------------------------------
# =============================================================================

Write-Host ""
$_sumInner = 56
Write-Host ("=" * $_sumInner) -ForegroundColor Cyan
Write-Host "  " -NoNewline; Write-Host "Prerequisites installed successfully!" -ForegroundColor Green
Write-Host ("=" * $_sumInner) -ForegroundColor Cyan
Write-Host ""

$gitVer = if (command_exists "git") { git --version } else { "see above" }
$uvVer  = if (command_exists "uv")  { uv --version }  else { "restart terminal to activate" }

Write-Ok "Git  $gitVer"
Write-Ok "uv   $uvVer"
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Note:" -ForegroundColor Yellow -NoNewline
Write-Host " If uv is not found in a new terminal, add its bin dir to your PATH:"
Write-Host '    $env:PATH = "$env:USERPROFILE\.local\bin;" + $env:PATH'
Write-Host ""
Write-Host "  Next: run the enterprise installer"
Write-Host "    .\enterprise_install.ps1"
Write-Host ""
