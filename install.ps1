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

# commands/rlm-mem
New-Item -ItemType Directory -Force -Path "$Target\commands\rlm-mem" | Out-Null
Copy-Item "$RepoDir\.claude\commands\rlm-mem\*" "$Target\commands\rlm-mem\" -Recurse -Force
Write-Host "  commands/rlm-mem: synced"

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

Write-Host ""
Write-Host "Done. Run /rlm-mem:discover:start to begin a session."
