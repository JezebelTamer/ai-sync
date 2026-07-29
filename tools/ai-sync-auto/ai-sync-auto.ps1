param(
    [string]$RepoPath = 'C:/Users/txzee/.ai-sync',
    [string]$CliPath = 'C:/Users/txzee/Documents/GitHub/MediaBot/ai-sync/dist/cli.js',
    [string]$NodePath = 'C:/Program Files/nodejs/node.exe'
)

$repo = $RepoPath
$cli = $CliPath
$node = $NodePath

if (-not (Test-Path $repo)) { exit 0 }
if (-not (Test-Path $cli)) { exit 0 }
if (-not (Test-Path $node)) { exit 0 }

Set-Location $repo
& $node $cli push --no-update-check --repo-path $repo | Out-Null
