param(
    [string]$RepoPath = 'C:/Users/txzee/.ai-sync',
    [string]$CliPath = 'C:/Users/txzee/Documents/GitHub/MediaBot/ai-sync/dist/cli.js',
    [string]$NodePath = 'C:/Program Files/nodejs/node.exe'
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$autoScript = Join-Path $scriptDir 'ai-sync-auto.ps1'
$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDir = Split-Path $profilePath -Parent

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$hook = @"
# ai-sync auto-push
if (Test-Path '$autoScript') {
    Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "$autoScript"' -WindowStyle Hidden
}
"@

if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

if (-not (Select-String -Path $profilePath -Pattern 'ai-sync auto-push' -SimpleMatch -Quiet)) {
    Add-Content -Path $profilePath -Value $hook
}

@"
param(
    [string]`$RepoPath = '$RepoPath',
    [string]`$CliPath = '$CliPath',
    [string]`$NodePath = '$NodePath'
)

`$repo = `$RepoPath
`$cli = `$CliPath
`$node = `$NodePath

if (-not (Test-Path `$repo)) { exit 0 }
if (-not (Test-Path `$cli)) { exit 0 }
if (-not (Test-Path `$node)) { exit 0 }

Set-Location `$repo
& `$node `$cli push --no-update-check --repo-path `$repo | Out-Null
"@ | Set-Content $autoScript

Write-Host "Bootstrap complete."
Write-Host "Profile: $profilePath"
Write-Host "Auto script: $autoScript"
