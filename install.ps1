param(
    [string]$SyncRepoUrl = 'https://github.com/JezebelTamer/ai-sync.git',
    [string]$SyncRepoPath = "$HOME/.ai-sync",
    [string]$AiSyncRepoUrl = 'https://github.com/berlinguyinca/ai-sync.git',
    [string]$AiSyncRepoPath = "$HOME/.ai-sync-tools/ai-sync"
)

$ErrorActionPreference = 'Stop'

function Ensure-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not available."
    }
}

Ensure-Command git
Ensure-Command node
Ensure-Command npm

if (-not (Test-Path $SyncRepoPath)) {
    Write-Host "Cloning sync repo from $SyncRepoUrl"
    git clone $SyncRepoUrl $SyncRepoPath | Out-Null
} else {
    Write-Host "Sync repo already exists at $SyncRepoPath"
    git -C $SyncRepoPath pull origin main | Out-Null
}

if (-not (Test-Path $AiSyncRepoPath)) {
    Write-Host "Cloning ai-sync tool repo from $AiSyncRepoUrl"
    git clone $AiSyncRepoUrl $AiSyncRepoPath | Out-Null
} else {
    Write-Host "ai-sync tool repo already exists at $AiSyncRepoPath"
    git -C $AiSyncRepoPath pull origin main | Out-Null
}

$nodeExe = (Get-Command node).Source
$npmExe = (Get-Command npm).Source

Set-Location $AiSyncRepoPath
npm install | Out-Null
npm run build | Out-Null
npm link | Out-Null

$cliPath = Join-Path $AiSyncRepoPath 'dist/cli.js'
$bootstrapScript = Join-Path $SyncRepoPath 'tools/ai-sync-auto/bootstrap-ai-sync-auto.ps1'

if (-not (Test-Path $bootstrapScript)) {
    throw "Bootstrap script not found: $bootstrapScript"
}

Write-Host "Installing sync config and skills"
& $nodeExe $cliPath bootstrap $SyncRepoUrl --no-update-check | Out-Null

Write-Host "Installing auto-sync hook"
& $bootstrapScript -RepoPath $SyncRepoPath -CliPath $cliPath -NodePath $nodeExe | Out-Null

Write-Host "Install complete."
Write-Host "Sync repo: $SyncRepoPath"
Write-Host "ai-sync CLI: $cliPath"
