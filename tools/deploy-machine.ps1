<#
.SYNOPSIS
    Full ai-sync deploy for a Windows machine: SSH auth, repo, CLI, profile
    hook, and the hourly scheduled task. Idempotent - safe to re-run.

.DESCRIPTION
    install.ps1 sets up the repo, CLI, config and profile hook. It stops short
    of the two things that make sync run unattended, because neither travels
    through sync itself:

      1. Push auth. ai-sync only syncs the claude/codex/antigravity config
         dirs, and a repo's remote URL lives in .git/config which is not
         tracked, so every machine clones over HTTPS and cannot push.
      2. The scheduled task. The profile hook only fires when a PowerShell
         window opens, so an idle machine never syncs.

    This script does install.ps1's job plus both of those.

    One manual beat remains and cannot be automated: GitHub has to be told
    about this machine's public key. The script generates the key, opens the
    browser to the right page, and waits. If you copied an existing key over
    beforehand, it detects that and never pauses at all.

.PARAMETER Owner
    GitHub account that owns the sync repo. Push fails if the key authenticates
    as anyone else, so this is checked rather than assumed.

.PARAMETER SkipTask
    Skip scheduled task registration (profile hook only).

.EXAMPLE
    # From a bare machine, one command:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $f=\"$env:TEMP\ai-sync-deploy.ps1\"; iwr -useb 'https://raw.githubusercontent.com/JezebelTamer/ai-sync/main/tools/deploy-machine.ps1' -OutFile $f; & $f; Remove-Item $f }"
#>
param(
    [string]$SyncRepoUrl  = 'https://github.com/JezebelTamer/ai-sync.git',
    [string]$SyncRepoPath = (Join-Path $HOME '.ai-sync'),
    [string]$Owner        = 'JezebelTamer',
    [string]$SshAlias     = 'github.com-jezebel',
    [string]$KeyPath      = (Join-Path $HOME '.ssh\id_rsa_jezebel'),
    [switch]$SkipTask
)

# 'Continue' because git, npm and ssh all write normal progress to stderr,
# which 'Stop' would treat as terminating.
$ErrorActionPreference = 'Continue'

function Write-Step { param([string]$Msg) Write-Host "`n[deploy] $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [!!] $Msg" -ForegroundColor Yellow }
function Die        { param([string]$Msg) Write-Host "`n[deploy] ERROR: $Msg" -ForegroundColor Red; exit 1 }

# -- 0. Pre-flight -------------------------------------------------------------

# Same host restriction as install.ps1: the profile hook targets the Windows
# PowerShell 5.1 console profile. Under pwsh 7 or an IDE host, $PROFILE points
# at a different file and the hook lands where 5.1 never loads it. Checked here
# so it fails on line one instead of halfway through a clone and npm build.
if (($PSVersionTable.PSEdition -and $PSVersionTable.PSEdition -ne 'Desktop') -or ($Host.Name -ne 'ConsoleHost')) {
    Die 'run this from the Windows PowerShell console (powershell.exe), not pwsh, ISE, or an IDE terminal.'
}

foreach ($cmd in 'git', 'node', 'npm', 'ssh', 'ssh-keygen') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Die "'$cmd' is required but not found. Install git (git-scm.com), Node (nodejs.org), and Windows OpenSSH."
    }
}
Write-OK 'git, node, npm, ssh present'

# -- 1. SSH auth ---------------------------------------------------------------

Write-Step 'Configuring SSH auth for GitHub'

$sshDir = Split-Path $KeyPath -Parent
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

$known = Join-Path $sshDir 'known_hosts'
if (-not (Test-Path $known)) { New-Item -ItemType File -Path $known -Force | Out-Null }

# Pre-seed github.com so the first connection cannot stall on a host-key prompt
# (BatchMode would fail it outright, which reads as an auth failure).
if (-not (Select-String -Path $known -Pattern '^github\.com' -Quiet -ErrorAction SilentlyContinue)) {
    & ssh-keyscan github.com 2>$null | Add-Content $known
    Write-OK 'github.com added to known_hosts'
}

# A dedicated Host alias, not a default-key override: these machines already
# have an id_rsa for a different GitHub account, and IdentitiesOnly stops ssh
# from offering it first and authenticating as the wrong user.
$sshConfig = Join-Path $sshDir 'config'
if (-not (Test-Path $sshConfig)) { New-Item -ItemType File -Path $sshConfig -Force | Out-Null }

if (-not (Select-String -Path $sshConfig -Pattern "Host\s+$([regex]::Escape($SshAlias))" -Quiet -ErrorAction SilentlyContinue)) {
    $keyForConfig = $KeyPath -replace [regex]::Escape($HOME), '~' -replace '\\', '/'
    Add-Content $sshConfig "`n# GitHub - $Owner account (ai-sync)"
    Add-Content $sshConfig "Host $SshAlias"
    Add-Content $sshConfig "    HostName github.com"
    Add-Content $sshConfig "    User git"
    Add-Content $sshConfig "    IdentityFile $keyForConfig"
    Add-Content $sshConfig "    IdentitiesOnly yes"
    Write-OK "Added Host $SshAlias to ssh config"
} else {
    Write-OK "Host $SshAlias already in ssh config"
}

# No passphrase: an unattended scheduled task has no agent and no one to prompt.
# '""' is how PS 5.1 passes an empty string through to a native exe.
if (-not (Test-Path $KeyPath)) {
    & ssh-keygen -t ed25519 -f $KeyPath -N '""' -C "ai-sync@$env:COMPUTERNAME" | Out-Null
    if (-not (Test-Path $KeyPath)) { Die "ssh-keygen did not produce $KeyPath" }
    Write-OK "Generated $KeyPath"
} else {
    Write-OK "Key already present at $KeyPath"
}

function Test-SshAuth {
    param([string]$Alias)
    # ssh always exits non-zero here because GitHub closes the session, so the
    # banner text is the only reliable signal.
    $out = & ssh -o BatchMode=yes -T "git@$Alias" 2>&1 | Out-String
    if ($out -match 'successfully authenticated' -and $out -match 'Hi ([^!]+)!') {
        return $matches[1].Trim()
    }
    return $null
}

$who = Test-SshAuth -Alias $SshAlias

if (-not $who) {
    # The one step that cannot be automated: adding a public key is an account
    # settings change on GitHub's side.
    $pub = Get-Content "$KeyPath.pub" -Raw
    Write-Host ''
    Write-Host '  ------------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host "  GitHub does not know this machine's key yet. Add it to the" -ForegroundColor Yellow
    Write-Host "  $Owner account, then come back here." -ForegroundColor Yellow
    Write-Host '  ------------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ''
    Write-Host $pub.Trim()
    Write-Host ''

    try {
        Set-Clipboard -Value $pub.Trim() -ErrorAction Stop
        Write-OK 'Key copied to clipboard'
    } catch {
        Write-Warn 'Could not reach the clipboard; copy the line above by hand.'
    }

    try { Start-Process 'https://github.com/settings/ssh/new' } catch {
        Write-Warn 'Open https://github.com/settings/ssh/new manually.'
    }

    for ($try = 1; $try -le 5; $try++) {
        Read-Host "  Paste it at github.com/settings/ssh/new (signed in as $Owner), then press Enter"
        $who = Test-SshAuth -Alias $SshAlias
        if ($who) { break }
        Write-Warn "Still not authenticating (attempt $try of 5). Check you are signed in as $Owner."
    }
    if (-not $who) { Die "SSH auth to git@$SshAlias never succeeded. Fix that, then re-run." }
}

if ($who -ne $Owner) {
    # Read would still work, so this fails loudly rather than at the first push.
    Die "SSH authenticated as '$who', but the repo is owned by '$Owner'. Push would be rejected. Add this machine's key to the $Owner account."
}
Write-OK "SSH authenticates as $who"

# -- 2. Repo + CLI + config + profile hook ------------------------------------

Write-Step 'Running install.ps1 (repo, CLI build, config pull, profile hook)'

if (-not (Test-Path $SyncRepoPath)) {
    & git clone --depth 1 $SyncRepoUrl $SyncRepoPath *>$null
    if (-not (Test-Path $SyncRepoPath)) { Die "git clone failed for $SyncRepoUrl" }
    Write-OK "Cloned to $SyncRepoPath"
}

$installer = Join-Path $SyncRepoPath 'install.ps1'
if (-not (Test-Path $installer)) { Die "install.ps1 not found in $SyncRepoPath" }

& $installer -SyncRepoUrl $SyncRepoUrl -SyncRepoPath $SyncRepoPath
if ($LASTEXITCODE -ne 0) { Die "install.ps1 failed (exit $LASTEXITCODE)" }

# -- 3. Push auth: swap the HTTPS remote for the SSH alias ---------------------

Write-Step 'Pointing the remote at SSH'

# install.ps1 clones over HTTPS, and HTTPS push needs an interactive credential
# prompt that a background job or scheduled task can never answer.
$sshRemote = "git@${SshAlias}:$Owner/ai-sync.git"
& git -C $SyncRepoPath remote set-url origin $sshRemote
Write-OK "origin -> $sshRemote"

# -- 4. Scheduled task ---------------------------------------------------------

$auto = Join-Path $SyncRepoPath 'tools\auto-sync.ps1'
if (-not (Test-Path $auto)) { Die "auto-sync.ps1 not found at $auto - sync repo out of date?" }

if (-not $SkipTask) {
    Write-Step 'Registering the ai-sync scheduled task'

    # -Mode Task, not Start: Start hands the work to Start-Job, and a background
    # job dies with its parent the moment a scheduled task's host exits.
    $arg = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $auto + '" -Mode Task'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg

    $me = "$env:USERDOMAIN\$env:USERNAME"

    $tLogon = New-ScheduledTaskTrigger -AtLogOn -User $me
    $tLogon.Delay = 'PT1M'

    # Duration is deliberately omitted: Task Scheduler reads a missing duration
    # as "repeat indefinitely", and TimeSpan::MaxValue is rejected outright.
    $tHourly = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(5) `
        -RepetitionInterval (New-TimeSpan -Hours 1)

    # StartWhenAvailable catches up a run missed while the machine slept.
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -MultipleInstances IgnoreNew

    # Interactive logon type keeps this password-free and leaves the user's
    # ~/.ssh readable, which an S4U or SYSTEM task would not.
    $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited

    try { Unregister-ScheduledTask -TaskName 'ai-sync' -Confirm:$false -ErrorAction Stop } catch {}

    Register-ScheduledTask -TaskName 'ai-sync' -Action $action -Trigger @($tLogon, $tHourly) `
        -Settings $settings -Principal $principal `
        -Description 'Hourly ai-sync pull+push of AI tool config.' | Out-Null

    Write-OK "Task 'ai-sync' registered (hourly, plus 1 min after logon)"
} else {
    Write-Warn 'Scheduled task skipped (-SkipTask); sync runs only when a PowerShell window opens.'
}

# -- 5. Prove it works ---------------------------------------------------------

Write-Step 'Verifying with a real sync'

& $auto -Mode Task

$log = Join-Path $SyncRepoPath '.auto-sync.log'
if (Test-Path $log) { Get-Content $log -Tail 6 | ForEach-Object { Write-Host "  $_" } }

$ahead = (& git -C $SyncRepoPath rev-list --count '@{u}..HEAD' 2>$null)
if ($ahead -and $ahead -ne '0') {
    Write-Warn "$ahead local commit(s) still unpushed - check the log above."
} else {
    Write-OK 'Repo is in sync with the remote'
}

Write-Host ''
Write-Host '[deploy] Done. Config syncs hourly and on every new PowerShell session.' -ForegroundColor Green
Write-Host '  Log    : ' -NoNewline; Write-Host $log
Write-Host '  Manual : ai-sync pull  /  ai-sync push'
Write-Host '  Remove : Unregister-ScheduledTask ai-sync -Confirm:$false'
