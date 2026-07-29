<#
.SYNOPSIS
    One-command installer for ai-sync across any Windows machine.

.DESCRIPTION
    Clones the sync config repo and the ai-sync CLI tool, builds the CLI,
    installs a PowerShell profile hook that auto-pulls on session start and
    auto-pushes on session exit. Fully idempotent - safe to re-run.

.PARAMETER SyncRepoUrl
    Git URL of the shared sync config repo (your settings, skills, etc.).

.PARAMETER ToolRepoUrl
    Git URL of the ai-sync CLI tool repo.

.PARAMETER SyncRepoPath
    Local path for the sync config repo. Defaults to ~/.ai-sync

.PARAMETER ToolRepoPath
    Local path for the ai-sync CLI tool. Defaults to ~/.ai-sync-tools/ai-sync

.EXAMPLE
    # Run from the internet - one command, fully automatic:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $f = \"$env:TEMP\\ai-sync-install.ps1\"; iwr -useb 'https://raw.githubusercontent.com/JezebelTamer/ai-sync/main/install.ps1' -OutFile $f; & $f; Remove-Item $f }"

    # Or clone and run directly:
    git clone --depth 1 https://github.com/JezebelTamer/ai-sync.git $HOME/.ai-sync; powershell -NoProfile -ExecutionPolicy Bypass -File $HOME/.ai-sync/install.ps1
#>
param(
    [string]$SyncRepoUrl  = 'https://github.com/JezebelTamer/ai-sync.git',
    [string]$ToolRepoUrl  = 'https://github.com/berlinguyinca/ai-sync.git',
    [string]$SyncRepoPath = (Join-Path $HOME '.ai-sync'),
    [string]$ToolRepoPath = (Join-Path $HOME '.ai-sync-tools/ai-sync')
)

Set-StrictMode -Version Latest
# Using 'Continue' because git and npm write to stderr for normal progress,
# which PowerShell's 'Stop' treats as terminating errors.
$ErrorActionPreference = 'Continue'

# -- Helpers -------------------------------------------------------------------

function Write-Step { param([string]$Msg) Write-Host "`n[ai-sync] $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }

function Assert-Command {
    param([string]$Name, [string]$HelpUrl)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Host "`n[ai-sync] ERROR: '$Name' is required but not found." -ForegroundColor Red
        if ($HelpUrl) { Write-Host "  Install it from: $HelpUrl" -ForegroundColor Yellow }
        exit 1
    }
}

function Clone-Or-Pull {
    param([string]$Url, [string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) {
        Write-Step "Cloning $Label"
        git clone --depth 1 $Url $Path *>$null
        if ($LASTEXITCODE -ne 0) { Write-Host "[ai-sync] ERROR: git clone failed for $Label" -ForegroundColor Red; exit 1 }
        Write-OK "Cloned to $Path"
    } else {
        Write-Step "Updating $Label"
        git -C $Path pull --ff-only origin main *>$null
        Write-OK "Updated $Path"
    }
}

# -- Pre-flight checks --------------------------------------------------------

Write-Step 'Checking prerequisites'
Assert-Command 'git'  'https://git-scm.com/downloads'
Assert-Command 'node' 'https://nodejs.org'
Assert-Command 'npm'  'https://nodejs.org'
Write-OK 'git, node, npm are available'

# -- 1. Clone / update repos --------------------------------------------------

Clone-Or-Pull -Url $SyncRepoUrl -Path $SyncRepoPath -Label 'sync config repo'
Clone-Or-Pull -Url $ToolRepoUrl -Path $ToolRepoPath -Label 'ai-sync CLI tool'

# -- 2. Build the ai-sync CLI -------------------------------------------------

$cliEntry = Join-Path (Join-Path $ToolRepoPath 'dist') 'cli.js'

if (-not (Test-Path $cliEntry)) {
    Write-Step 'Building ai-sync CLI (first run - this takes a moment)'
} else {
    Write-Step 'Rebuilding ai-sync CLI'
}

Push-Location $ToolRepoPath
try {
    npm install --no-audit --no-fund *>$null
    npm run build *>$null
}
finally {
    Pop-Location
}

if (-not (Test-Path $cliEntry)) {
    Write-Host "`n[ai-sync] ERROR: CLI build failed - $cliEntry not found." -ForegroundColor Red
    exit 1
}
Write-OK "CLI ready at $cliEntry"

# -- 3. Initialize ai-sync environments ---------------------------------------

Write-Step 'Initializing ai-sync environments'
$nodePath = (Get-Command node).Source

& $nodePath $cliEntry init --no-update-check --repo-path $SyncRepoPath *>$null
Write-OK 'ai-sync initialized'

# -- 4. Install the PowerShell profile hook ------------------------------------

Write-Step 'Installing PowerShell profile hook'

$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDir  = Split-Path $profilePath -Parent

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

# The hook marker - used for idempotent detection and clean removal
$hookMarker = '# >>> ai-sync auto-sync >>>'
$hookEnd    = '# <<< ai-sync auto-sync <<<'

# Escape paths for embedding in the generated script block
$escapedSyncRepo = $SyncRepoPath -replace "'", "''"

# Build the hook block. Uses the resolved paths so it works on any machine.
$hookBlock = @"
$hookMarker
# Installed by ai-sync install.ps1 - do not edit this block manually.
`$_aiSyncRepo = '$escapedSyncRepo'

# Pull latest config on session start (silent, background)
if ((Test-Path `$_aiSyncRepo)) {
    Start-Job -ScriptBlock {
        param(`$r)
        Set-Location `$r
        git pull --ff-only origin main *>`$null
    } -ArgumentList `$_aiSyncRepo | Out-Null
}

# Push config changes on session exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    `$r = '$escapedSyncRepo'
    if (Test-Path `$r) {
        Set-Location `$r
        git add -A *>`$null
        git diff --cached --quiet *>`$null
        if (`$LASTEXITCODE -ne 0) {
            `$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            git commit -m "sync: auto-push `$ts from `$env:COMPUTERNAME" *>`$null
            git push origin main *>`$null
        }
    }
} | Out-Null
$hookEnd
"@

# Remove any existing hook block first (idempotent re-install)
if (Test-Path $profilePath) {
    $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($content -and ($content -match [regex]::Escape($hookMarker))) {
        $pattern = [regex]::Escape($hookMarker) + '[\s\S]*?' + [regex]::Escape($hookEnd) + '\r?\n?'
        $content = [regex]::Replace($content, $pattern, '')
        Set-Content -Path $profilePath -Value $content.TrimEnd() -NoNewline
    }
}

# Append the new hook block
Add-Content -Path $profilePath -Value "`n$hookBlock`n"
Write-OK "Profile hook installed at $profilePath"

# -- 5. Summary ---------------------------------------------------------------

Write-Host ''
Write-Host '===========================================================' -ForegroundColor Green
Write-Host '  ai-sync installation complete!' -ForegroundColor Green
Write-Host '===========================================================' -ForegroundColor Green
Write-Host ''
Write-Host "  Sync repo    : $SyncRepoPath" -ForegroundColor White
Write-Host "  CLI tool     : $cliEntry" -ForegroundColor White
Write-Host "  Profile hook : $profilePath" -ForegroundColor White
Write-Host ''
Write-Host '  What happens automatically:' -ForegroundColor Yellow
Write-Host '    - On session start : pulls latest config from GitHub'
Write-Host '    - On session exit  : pushes local changes to GitHub'
Write-Host ''
Write-Host '  Environments configured:' -ForegroundColor Yellow
$envFile = Join-Path $SyncRepoPath '.environments.json'
if (Test-Path $envFile) {
    $envs = Get-Content $envFile | ConvertFrom-Json
    foreach ($e in $envs) { Write-Host "    - $e" }
} else {
    Write-Host '    (none yet - run ai-sync env enable <name>)'
}
Write-Host ''
Write-Host '  To install on another machine, run:' -ForegroundColor Yellow
Write-Host '    powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $f = \"$env:TEMP\ai-sync-install.ps1\"; iwr -useb ''https://raw.githubusercontent.com/JezebelTamer/ai-sync/main/install.ps1'' -OutFile $f; & $f; Remove-Item $f }"'
Write-Host ''
