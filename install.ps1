<#
.SYNOPSIS
    One-command installer for ai-sync across any Windows machine.

.DESCRIPTION
    Clones the sync config repo and the ai-sync CLI tool, builds the CLI,
    applies the synced config to this machine (ai-sync pull), and installs a
    PowerShell profile hook that applies fresh config on session start and
    captures/pushes local changes on session exit. Fully idempotent - safe
    to re-run.

    All CLI calls go through tools/ai-sync.mjs in the sync repo: dist/cli.js
    only self-executes when process.argv[1] ends with a forward-slash path,
    which never matches on Windows, so invoking it directly is a silent no-op.

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

# -- 3. Apply synced config to this machine -----------------------------------
# NOT "init": init CAPTURES local config into a fresh repo (first-machine
# setup). On a machine being set up from the shared repo the correct direction
# is pull, which APPLIES the repo payload to the local config directories.

Write-Step 'Applying synced config (ai-sync pull)'
$nodePath = (Get-Command node).Source
$wrapper  = Join-Path $SyncRepoPath 'tools\ai-sync.mjs'
$logFile  = Join-Path $SyncRepoPath '.ai-sync-install.log'

if (-not (Test-Path $wrapper)) {
    Write-Host "`n[ai-sync] ERROR: launcher not found at $wrapper - sync repo out of date?" -ForegroundColor Red
    exit 1
}

& $nodePath $wrapper --no-update-check pull *>> $logFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ai-sync] ERROR: ai-sync pull failed - see $logFile" -ForegroundColor Red
    exit 1
}
Write-OK 'Synced config applied to local directories'

& $nodePath $wrapper --no-update-check install-skills *>> $logFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ai-sync] WARNING: install-skills failed - see $logFile" -ForegroundColor Yellow
} else {
    Write-OK 'Slash commands installed (/sync)'
}

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
# Session start: APPLY the latest synced config (ai-sync pull, background,
# throttled to once per hour). Session exit: CAPTURE local config changes and
# publish them (ai-sync push). Both go through tools/ai-sync.mjs because
# invoking dist/cli.js directly is a silent no-op on Windows.
`$_aiSyncRepo = '$escapedSyncRepo'
`$_aiSyncCli  = Join-Path `$_aiSyncRepo 'tools\ai-sync.mjs'
`$_aiSyncLog  = Join-Path `$_aiSyncRepo '.auto-sync.log'

function global:ai-sync { & node '$escapedSyncRepo\tools\ai-sync.mjs' @args }

if (Test-Path `$_aiSyncCli) {
    if ((Test-Path `$_aiSyncLog) -and ((Get-Item `$_aiSyncLog).Length -gt 1MB)) { Clear-Content `$_aiSyncLog }
    `$_aiSyncStamp = Join-Path `$_aiSyncRepo '.last-auto-pull'
    `$_aiSyncDue = (-not (Test-Path `$_aiSyncStamp)) -or (((Get-Date) - (Get-Item `$_aiSyncStamp).LastWriteTime).TotalMinutes -ge 60)
    if (`$_aiSyncDue) {
        New-Item -ItemType File -Path `$_aiSyncStamp -Force | Out-Null
        Start-Job -ScriptBlock {
            param(`$cli, `$log)
            & node `$cli --no-update-check pull *>> `$log
        } -ArgumentList `$_aiSyncCli, `$_aiSyncLog | Out-Null
    }
}

Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    `$repo = '$escapedSyncRepo'
    `$cli  = Join-Path `$repo 'tools\ai-sync.mjs'
    if (Test-Path `$cli) {
        & node `$cli --no-update-check push *>> (Join-Path `$repo '.auto-sync.log')
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
Write-Host '    - On session start : ai-sync pull applies latest config (hourly, background)'
Write-Host '    - On session exit  : ai-sync push captures and publishes local changes'
Write-Host '    - ai-sync is available as a command in new PowerShell sessions'
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
