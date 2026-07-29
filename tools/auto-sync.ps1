# ai-sync automatic sync driver, invoked by the PowerShell profile hook:
#   auto-sync.ps1 -Mode Start   session start: throttled background pull+push
#   auto-sync.ps1 -Mode Exit    clean session exit: best-effort bounded push
#
# Lives in the sync repo so behavior changes ship through sync itself; the
# profile hook only needs reinstalling when this file's interface changes.
#
# push always passes --skip-discovery: without it the engine's tool discovery
# auto-migrates the repo to a v3 layout that its own push/pull branches do not
# handle yet (they test version === 2), which would silently flip every
# machine onto the legacy flat format.
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'Exit')]
    [string]$Mode
)

$repo  = Split-Path $PSScriptRoot -Parent
$cli   = Join-Path $PSScriptRoot 'ai-sync.mjs'
$log   = Join-Path $repo '.auto-sync.log'
$stamp = Join-Path $repo '.last-auto-pull'
$lock  = Join-Path $repo '.sync.lock'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return }
if (-not (Test-Path $cli)) { return }

if ($Mode -eq 'Start') {
    # Trim the log past 1MB; a sharing violation from a concurrent writer just
    # means it gets trimmed by a later session instead.
    try {
        if ((Test-Path $log -PathType Leaf) -and ((Get-Item $log).Length -gt 1MB)) {
            Clear-Content $log -ErrorAction Stop
        }
    } catch {}

    $due = (-not (Test-Path $stamp)) -or
        (((Get-Date) - (Get-Item $stamp).LastWriteTime).TotalMinutes -ge 60)
    if (-not $due) { return }
    New-Item -ItemType File -Path $stamp -Force | Out-Null

    Start-Job -ScriptBlock {
        param($repo, $cli, $log, $lock)
        # Cross-session mutex; a crashed holder goes stale after 10 minutes.
        try {
            if (Test-Path $lock) {
                if (((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes -lt 10) { return }
                Remove-Item $lock -Force -ErrorAction Stop
            }
            New-Item -ItemType File -Path $lock -ErrorAction Stop | Out-Null
        } catch { return }
        try {
            & node $cli --no-update-check pull *>> $log
            # Never push a repo wedged mid-merge: conflict markers would be
            # committed and pulled onto every other machine.
            if (Test-Path (Join-Path $repo '.git\MERGE_HEAD')) {
                Add-Content $log '[auto-sync] merge pending, push skipped'
            } else {
                & node $cli --no-update-check push --skip-discovery *>> $log
            }
            # Upstream never prunes ~/.ai-sync-backups and every pull writes a
            # full backup; keep the newest 20.
            $backups = Join-Path (Split-Path $repo -Parent) '.ai-sync-backups'
            if (Test-Path $backups) {
                Get-ChildItem $backups -Directory |
                    Sort-Object Name -Descending |
                    Select-Object -Skip 20 |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        } finally {
            Remove-Item $lock -Force -ErrorAction SilentlyContinue
        }
    } -ArgumentList $repo, $cli, $log, $lock | Out-Null
    return
}

# Exit mode: push only, bounded so a half-open network connection cannot hang
# the closing shell. PowerShell.Exiting fires on 'exit', not on window close,
# so this is best-effort; the session-start job is the reliable path.
if (Test-Path (Join-Path $repo '.git\MERGE_HEAD')) { return }
try {
    if (Test-Path $lock) {
        if (((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes -lt 10) { return }
        Remove-Item $lock -Force -ErrorAction Stop
    }
    New-Item -ItemType File -Path $lock -ErrorAction Stop | Out-Null
} catch { return }
try {
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    # Pre-quote the path: PS 5.1 Start-Process does not quote ArgumentList
    # elements that contain spaces.
    $p = Start-Process -FilePath node -ArgumentList @("`"$cli`"", '--no-update-check', 'push', '--skip-discovery') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $p.WaitForExit(30000)) {
        try { $p.Kill() } catch {}
        Add-Content $log '[auto-sync] exit push timed out after 30s'
    }
    foreach ($f in @($out, $err)) {
        $text = Get-Content $f -Raw -ErrorAction SilentlyContinue
        if ($text) { Add-Content $log $text }
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
