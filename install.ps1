# install.ps1 - sync this repo's .claude/ files to ~/.claude/
# Run after cloning or after making changes in .claude/ to update your installation.
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = "$env:USERPROFILE\.claude"

# -----------------------------------------------------------------------
# Requirements check
# -----------------------------------------------------------------------
Write-Host "Checking requirements..."
Write-Host ""
$missingRequired = $false
$missingOptional = @()

# --- Required ---

# Python 3.8+
$python = Get-Command python -ErrorAction SilentlyContinue
$python3 = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python -and -not $python3) {
    Write-Host "  [MISSING] Python 3.8+ - required for RLM REPL"
    Write-Host "    winget install Python.Python.3"
    Write-Host "    or: https://www.python.org/downloads/"
    $missingRequired = $true
} else {
    $pyCmd = if ($python3) { "python3" } else { "python" }
    $pyVer = & $pyCmd --version 2>&1
    Write-Host "  [OK] $pyVer"
}

# Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  [MISSING] Git - required for version control and RLM file indexing"
    Write-Host "    winget install Git.Git"
    Write-Host "    or: https://git-scm.com/download/win"
    $missingRequired = $true
} else {
    Write-Host "  [OK] $(git --version)"
}

# Claude Code
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "  [MISSING] Claude Code - required CLI"
    Write-Host "    Install: https://claude.ai/download"
    $missingRequired = $true
} else {
    Write-Host "  [OK] Claude Code found"
}

# --- Optional (with impact notes) ---

# bash (hooks + statusline)
$bashAvailable = $null -ne (Get-Command bash -ErrorAction SilentlyContinue)
if (-not $bashAvailable) {
    Write-Host "  [SKIP] bash - not found; hooks and statusline will NOT be installed"
    Write-Host "         Without bash, context-guard hook cannot run."
    Write-Host "         WARNING: if .sh hooks are already in settings.json,"
    Write-Host "         prompts will be silently dropped in Claude Code."
    Write-Host "         Install options:"
    Write-Host "           winget install Git.Git  (Git Bash - simplest)"
    Write-Host "           wsl --install           (WSL - full Linux)"
    $missingOptional += "bash"
} else {
    Write-Host "  [OK] bash - hooks and statusline will be installed"
}

# jq (statusline JSON parsing, install.sh settings.json patching)
$jqAvailable = $null -ne (Get-Command jq -ErrorAction SilentlyContinue)
if (-not $jqAvailable) {
    Write-Host "  [SKIP] jq - not found; statusline auto-config unavailable"
    Write-Host "         statusline.sh requires jq at runtime to display context info."
    Write-Host "         Install: winget install jqlang.jq"
    Write-Host "         or: https://jqlang.github.io/jq/download/"
    $missingOptional += "jq"
} else {
    Write-Host "  [OK] jq $(jq --version 2>&1)"
}

# gh (GitHub CLI - PR creation)
$ghAvailable = $null -ne (Get-Command gh -ErrorAction SilentlyContinue)
if (-not $ghAvailable) {
    Write-Host "  [SKIP] gh - not found; /dev:git pr will print descriptions for manual paste"
    Write-Host "         Install: winget install GitHub.cli"
    $missingOptional += "gh"
} else {
    Write-Host "  [OK] $(gh --version 2>&1 | Select-Object -First 1)"
}

# Node.js (claude-mem plugin)
$nodeAvailable = $null -ne (Get-Command node -ErrorAction SilentlyContinue)
if (-not $nodeAvailable) {
    Write-Host "  [SKIP] Node.js - not found; claude-mem plugin may not install"
    Write-Host "         Claude-mem requires Node.js for its worker service."
    Write-Host "         Install: winget install OpenJS.NodeJS.LTS"
    $missingOptional += "node"
} else {
    Write-Host "  [OK] node $(node --version 2>&1)"
}

# --- Summary ---
Write-Host ""
if ($missingRequired) {
    Write-Host "ERROR: Required dependencies are missing. Install them and re-run install.ps1."
    exit 1
}
if ($missingOptional.Count -gt 0) {
    Write-Host "Optional dependencies missing: $($missingOptional -join ', ')"
    Write-Host "Installation will proceed, but some features will be unavailable."
    Write-Host ""
    $yn = Read-Host "Continue anyway? [Y/n]"
    if ($yn -match '^[Nn]') {
        Write-Host "Aborted. Install missing dependencies and re-run."
        exit 0
    }
}

Write-Host ""
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
# .sh hooks require bash (WSL or Git Bash). Without it, hooks registered in
# settings.json will fail silently on UserPromptSubmit - causing prompts to
# be dropped. Only install if bash is available.
$hooksDir = "$RepoDir\.claude\hooks"
if (Test-Path "$hooksDir\*.sh") {
    $bashAvailable = $null -ne (Get-Command bash -ErrorAction SilentlyContinue)
    if ($bashAvailable) {
        New-Item -ItemType Directory -Force -Path "$Target\hooks" | Out-Null
        Copy-Item "$hooksDir\*.sh" "$Target\hooks\" -Force
        $hookCount = (Get-ChildItem "$hooksDir\*.sh").Count
        Write-Host "  hooks: $hookCount files (bash found - hooks installed)"
    } else {
        Write-Host "  hooks: SKIPPED - bash not found (install WSL or Git Bash to enable hooks)"
        Write-Host "  WARNING: if settings.json already references these hooks, prompts will be"
        Write-Host "  dropped silently. Remove hook entries from ~/.claude/settings.json if so."
    }
}

# rlm_scripts
New-Item -ItemType Directory -Force -Path "$Target\rlm_scripts" | Out-Null
Copy-Item "$RepoDir\.claude\rlm_scripts\*.py" "$Target\rlm_scripts\" -Force
$scriptCount = (Get-ChildItem "$RepoDir\.claude\rlm_scripts\*.py").Count
Write-Host "  rlm_scripts: $scriptCount files"

# statusline
$statuslineSrc = "$RepoDir\.claude\statusline.sh"
if (Test-Path $statuslineSrc) {
    $bashAvailable = $null -ne (Get-Command bash -ErrorAction SilentlyContinue)
    if ($bashAvailable) {
        Copy-Item $statuslineSrc "$Target\statusline.sh" -Force
        Write-Host "  statusline: copied to $Target\statusline.sh"
        Write-Host "  Note: add to ~/.claude/settings.json manually:"
        Write-Host '  { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }'
    } else {
        Write-Host "  statusline: SKIPPED - bash not found (statusline.sh requires bash)"
    }
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
        Write-Host "  skipped - remove manually: Remove-Item -Recurse $oldRlmMem"
    }
}
$oldHook = "$Target\hooks\docs-first-guard.sh"
if (Test-Path $oldHook) {
    $yn = Read-Host "  Deprecated docs-first-guard hook found. Remove? [Y/n]"
    if ($yn -notmatch '^[Nn]') {
        Remove-Item $oldHook -Force
        Write-Host "  removed docs-first-guard.sh"
    } else {
        Write-Host "  skipped - remove manually: Remove-Item $oldHook"
    }
}

# fix stale .sh hook registrations in settings.json when bash is not available
# hooks referencing .sh files will cause prompts to be silently dropped
$bashAvailable = $null -ne (Get-Command bash -ErrorAction SilentlyContinue)
if (-not $bashAvailable) {
    $settingsFile = "$Target\settings.json"
    if (Test-Path $settingsFile) {
        $settingsRaw = Get-Content $settingsFile -Raw
        # check if settings.json references any .sh hooks
        if ($settingsRaw -match '\.sh') {
            Write-Host ""
            Write-Host "  WARNING: settings.json contains .sh hook references but bash is not available."
            Write-Host "  This causes prompts to be silently dropped in Claude Code."
            Write-Host "  Affected file: $settingsFile"
            $yn = Read-Host "  Remove .sh hook entries from settings.json? [Y/n]"
            if ($yn -notmatch '^[Nn]') {
                # parse JSON, remove hooks entries that reference .sh files
                $settings = $settingsRaw | ConvertFrom-Json
                if ($settings.hooks) {
                    $hookKeys = @($settings.hooks.PSObject.Properties.Name)
                    foreach ($key in $hookKeys) {
                        $entries = $settings.hooks.$key
                        $filtered = @($entries | Where-Object {
                            # keep entries that don't reference .sh commands
                            $cmd = $_.hooks | ForEach-Object { $_.command }
                            -not ($cmd -match '\.sh')
                        })
                        $settings.hooks.$key = $filtered
                    }
                    # remove empty hook event arrays
                    $hookKeys = @($settings.hooks.PSObject.Properties.Name)
                    foreach ($key in $hookKeys) {
                        if ($settings.hooks.$key.Count -eq 0) {
                            $settings.hooks.PSObject.Properties.Remove($key)
                        }
                    }
                }
                # also remove statusLine if it references a .sh file
                if ($settings.statusLine -and $settings.statusLine.command -match '\.sh') {
                    $settings.PSObject.Properties.Remove('statusLine')
                    Write-Host "  removed statusLine (.sh reference)"
                }
                $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
                Write-Host "  settings.json: .sh hook entries removed"
                Write-Host "  Restart Claude Code for the change to take effect."
            } else {
                Write-Host "  skipped - edit $settingsFile manually to remove .sh hook entries"
            }
        }
    }
}

Write-Host ""
Write-Host "Done. Run /dev:start to begin a session."
