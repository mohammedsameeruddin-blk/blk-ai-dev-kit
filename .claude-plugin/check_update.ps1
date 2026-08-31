# DEPRECATED: The databricks-ai-dev-kit Claude Code plugin is no longer published
# (see .claude-plugin/DEPRECATED.md). Install skills via install.ps1 or
# `databricks aitools install`. This script is kept for reference and still runs
# if invoked directly.
#
# Version update check for Databricks AI Dev Kit (Windows / PowerShell equivalent
# of check_update.sh). Stdout is injected as context Claude can see at session start.
# Silent on success (up to date) or failure (network error, missing files).

$ErrorActionPreference = "SilentlyContinue"

$RemoteUrl  = "https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/VERSION"
$CacheFile  = Join-Path $env:USERPROFILE ".ai-dev-kit\.update-check"
$CacheTtl   = 86400  # 24 hours

# Locate installed version file — check multiple candidates.
$versionFile = $null
$candidates = @(
    if ($env:CLAUDE_PLUGIN_ROOT)  { Join-Path $env:CLAUDE_PLUGIN_ROOT  "VERSION" }
    if ($env:CLAUDE_PROJECT_DIR)  { Join-Path $env:CLAUDE_PROJECT_DIR  ".ai-dev-kit\version" }
    (Join-Path $env:USERPROFILE   ".ai-dev-kit\version")
    (Join-Path (Split-Path $PSScriptRoot -Parent) "VERSION")
)
foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { $versionFile = $c; break }
}
if (-not $versionFile) { exit 0 }

$localVer = (Get-Content $versionFile -Raw 2>$null).Trim()
if (-not $localVer) { exit 0 }

$remoteVer = ""

# Check cache.
if (Test-Path $CacheFile) {
    $lines      = Get-Content $CacheFile 2>$null
    $cachedTs   = ($lines | Where-Object { $_ -match "^TIMESTAMP=" }  | Select-Object -First 1) -replace "^TIMESTAMP=",  ""
    $cachedVer  = ($lines | Where-Object { $_ -match "^REMOTE_VERSION=" } | Select-Object -First 1) -replace "^REMOTE_VERSION=", ""
    $now        = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($cachedTs -and $cachedVer -and (($now - [int]$cachedTs) -lt $CacheTtl)) {
        $remoteVer = $cachedVer.Trim()
    }
}

# Fetch if cache is stale.
if (-not $remoteVer) {
    try {
        $fetched = (Invoke-WebRequest -Uri $RemoteUrl -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop).Content.Trim()
        if ($fetched -and $fetched -notmatch "404|Not Found|error") {
            $remoteVer = $fetched
            $now       = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $cacheDir  = Split-Path $CacheFile -Parent
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            Set-Content -Path $CacheFile -Value "TIMESTAMP=$now`nREMOTE_VERSION=$remoteVer" -NoNewline
        }
    } catch {}
    if (-not $remoteVer) { exit 0 }
}

# Only nudge when the remote version is strictly newer.
# Parse major.minor.patch and compare numerically to avoid string-sort surprises.
function Compare-Version {
    param([string]$A, [string]$B)
    # Returns -1 if A < B, 0 if equal, 1 if A > B
    $pa = $A -split "\." | ForEach-Object { [int]$_ }
    $pb = $B -split "\." | ForEach-Object { [int]$_ }
    for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
        $va = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $vb = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($va -lt $vb) { return -1 }
        if ($va -gt $vb) { return  1 }
    }
    return 0
}

if ($remoteVer -and $remoteVer -ne $localVer) {
    if ((Compare-Version $localVer $remoteVer) -lt 0) {
        Write-Output "[ai-dev-kit] Update available: installed v${localVer}, latest v${remoteVer}. Worth mentioning"
        Write-Output "to the user near the start of your reply. For how to update, refer them to the `"Update`" section"
        Write-Output "of the ai-dev-kit README: https://github.com/databricks-solutions/ai-dev-kit#update"
    }
}
