# install.ps1 — sync this repo's .claude/ files to ~/.claude/
# Run after cloning or after making changes in .claude/ to update your installation.
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = "$env:USERPROFILE\.claude"

# -----------------------------------------------------------------------
# Requirements check
# -----------------------------------------------------------------------
Write-Host "Checking requirements..."
$missingRequired = $false

# Python 3
$python = Get-Command python -ErrorAction SilentlyContinue
$python3 = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python -and -not $python3) {
    Write-Host "  [MISSING] Python 3 — required for RLM REPL"
    Write-Host "    Install: https://www.python.org/downloads/"
    Write-Host "    Or via winget: winget install Python.Python.3"
    $missingRequired = $true
} else {
    $pyCmd = if ($python3) { "python3" } else { "python" }
    $pyVer = & $pyCmd --version 2>&1
    Write-Host "  [OK] $pyVer"
}

# Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  [MISSING] Git — required to clone and update this repo"
    Write-Host "    Install: https://git-scm.com/download/win"
    Write-Host "    Or via winget: winget install Git.Git"
    $missingRequired = $true
} else {
    Write-Host "  [OK] git $(git --version)"
}

# bash (optional but required for hooks and statusline)
$bashAvailable = $null -ne (Get-Command bash -ErrorAction SilentlyContinue)
if (-not $bashAvailable) {
    Write-Host "  [OPTIONAL] bash — not found; hooks and statusline will be skipped"
    Write-Host "    Hooks are required for context window warnings."
    Write-Host "    Without bash, any .sh hook already registered in settings.json"
    Write-Host "    will cause prompts to be silently dropped in Claude Code."
    Write-Host "    To install bash, choose one:"
    Write-Host "      Option A — WSL (recommended):"
    Write-Host "        wsl --install"
    Write-Host "        (then reopen PowerShell)"
    Write-Host "      Option B — Git for Windows (includes Git Bash):"
    Write-Host "        winget install Git.Git"
    Write-Host "        (ensure 'Add to PATH' is checked during install)"
    Write-Host "      Option C — MSYS2:"
    Write-Host "        winget install MSYS2.MSYS2"
} else {
    Write-Host "  [OK] bash available — hooks will be installed"
}

if ($missingRequired) {
    Write-Host ""
    Write-Host "ERROR: Required dependencies are missing. Install them and re-run install.ps1."
    exit 1
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
# settings.json will fail silently on UserPromptSubmit — causing prompts to
# be dropped. Only install if bash is available.
$hooksDir = "$RepoDir\.claude\hooks"
if (Test-Path "$hooksDir\*.sh") {
    $bashAvailable = $null -ne (Get-Command bash -ErrorAction SilentlyContinue)
    if ($bashAvailable) {
        New-Item -ItemType Directory -Force -Path "$Target\hooks" | Out-Null
        Copy-Item "$hooksDir\*.sh" "$Target\hooks\" -Force
        $hookCount = (Get-ChildItem "$hooksDir\*.sh").Count
        Write-Host "  hooks: $hookCount files (bash found — hooks installed)"
    } else {
        Write-Host "  hooks: SKIPPED — bash not found (install WSL or Git Bash to enable hooks)"
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
        Write-Host "  statusline: SKIPPED — bash not found (statusline.sh requires bash)"
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
                Write-Host "  skipped — edit $settingsFile manually to remove .sh hook entries"
            }
        }
    }
}

Write-Host ""
Write-Host "Done. Run /dev:start to begin a session."
