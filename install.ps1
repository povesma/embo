# install.ps1 — sync this repo's .claude/ files to ~/.claude/
# Run after cloning or after making changes in .claude/ to update your installation.
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = "$env:USERPROFILE\.claude"

Write-Host "Syncing from $RepoDir\.claude\ to $Target\"

# agents
New-Item -ItemType Directory -Force -Path "$Target\agents" | Out-Null
Copy-Item "$RepoDir\.claude\agents\*.md" "$Target\agents\" -Force
$agentCount = (Get-ChildItem "$RepoDir\.claude\agents\*.md").Count
Write-Host "  agents: $agentCount files"

# commands/dev
New-Item -ItemType Directory -Force -Path "$Target\commands\dev" | Out-Null
Copy-Item "$RepoDir\.claude\commands\dev\*" "$Target\commands\dev\" -Recurse -Force
Write-Host "  commands/dev: synced"

# profiles
New-Item -ItemType Directory -Force -Path "$Target\profiles" | Out-Null
Copy-Item "$RepoDir\.claude\profiles\*.yaml" "$Target\profiles\" -Force
$profileCount = (Get-ChildItem "$RepoDir\.claude\profiles\*.yaml").Count
Write-Host "  profiles: $profileCount files"

# hooks
$hooksDir = "$RepoDir\.claude\hooks"
if (Test-Path "$hooksDir\*.sh") {
    New-Item -ItemType Directory -Force -Path "$Target\hooks" | Out-Null
    Copy-Item "$hooksDir\*.sh" "$Target\hooks\" -Force
    $hookCount = (Get-ChildItem "$hooksDir\*.sh").Count
    Write-Host "  hooks: $hookCount files"
}

# rlm_scripts
New-Item -ItemType Directory -Force -Path "$Target\rlm_scripts" | Out-Null
Copy-Item "$RepoDir\.claude\rlm_scripts\*.py" "$Target\rlm_scripts\" -Force
$scriptCount = (Get-ChildItem "$RepoDir\.claude\rlm_scripts\*.py").Count
Write-Host "  rlm_scripts: $scriptCount files"

# statusline
$statuslineSrc = "$RepoDir\.claude\statusline.sh"
if (Test-Path $statuslineSrc) {
    Copy-Item $statuslineSrc "$Target\statusline.sh" -Force
    Write-Host "  statusline: copied to $Target\statusline.sh"
    Write-Host "  Note: configure statusLine in settings.json manually (jq not available on Windows):"
    Write-Host '  { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }'
}

# clean up old files
$oldRlmMem = "$Target\commands\rlm-mem"
if (Test-Path $oldRlmMem) {
    Write-Host ""
    $yn = Read-Host "  Old /rlm-mem:* commands found. Remove? [Y/n]"
    if ($yn -notmatch '^[Nn]') {
        Remove-Item $oldRlmMem -Recurse -Force
        Write-Host "  removed $oldRlmMem"
    } else {
        Write-Host "  skipped — remove manually: Remove-Item -Recurse $oldRlmMem"
    }
}
$oldHook = "$Target\hooks\docs-first-guard.sh"
if (Test-Path $oldHook) {
    $yn = Read-Host "  Deprecated docs-first-guard hook found. Remove? [Y/n]"
    if ($yn -notmatch '^[Nn]') {
        Remove-Item $oldHook -Force
        Write-Host "  removed docs-first-guard.sh"
    } else {
        Write-Host "  skipped — remove manually: Remove-Item $oldHook"
    }
}

Write-Host ""
Write-Host "Done. Run /dev:start to begin a session."
