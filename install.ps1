<#
.SYNOPSIS
  embo dependency installer (default) and manual standalone installer
  (-Standalone) for Windows. PowerShell parity with install.sh.

.DESCRIPTION
  RECOMMENDED INSTALL IS THE PLUGIN, not this script. Inside Claude Code:
    /plugin marketplace add povesma/embo
    /plugin install embo@embo
    /plugin install claude-mem      (from thedotmack/claude-mem)
  The plugin still needs the system dependencies below, so run this
  script in its default mode to get them, then install the plugins.

  Modes:
    .\install.ps1               Install/verify dependencies only
                                (Python, Node, jq, bun, uv). Use this
                                with the plugin install.
    .\install.ps1 -Standalone   Dependencies, THEN copy embo into
                                ~/.claude/ as a manual (no-plugin)
                                install. Do NOT combine -Standalone with
                                the plugin — they register the same hooks
                                and commands and would collide. Remove a
                                standalone install with uninstall.ps1.

  Hooks need bash (Git for Windows provides it); without bash, .sh hooks
  registered in settings.json silently drop prompts, so -Standalone skips
  hook registration when bash is absent. settings.json is edited with
  native ConvertFrom-Json/ConvertTo-Json — no jq needed by this script
  (the plugin's hooks still use jq at runtime, so jq is installed as a
  dependency).

  Run with:  powershell -ExecutionPolicy Bypass -File install.ps1 [-Standalone]

.PARAMETER Standalone
  Also copy embo into ~/.claude/ as a manual install.
.PARAMETER Force
  Non-interactive; skip prompts (default answer: no).
.PARAMETER Yes
  With -Force, auto-accept all prompts.
#>
[CmdletBinding()]
param(
    [switch]$Standalone,
    [switch]$Force,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$script:Skipped = 0
$script:DepsMissing = $false

$Target = Join-Path $env:USERPROFILE '.claude'
$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src = Join-Path $RepoDir 'plugin'

function Confirm-Step {
    param([string]$Prompt, [string]$Default = 'n')
    if ($Force) {
        if ($Yes) { return $true }
        $script:Skipped++
        return $false
    }
    $ans = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($ans)) { $ans = $Default }
    return $ans -match '^[Yy]'
}

# Get-Command, but reject the Microsoft Store "WindowsApps" stubs that
# masquerade as python/node and open the Store instead of running.
function Test-Cmd {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    if ($cmd.Source -match 'WindowsApps') { return $false }
    return $true
}

# Read/modify/write a JSON settings file with native cmdlets.
# ConvertTo-Json defaults to -Depth 2 (silently truncates nesting) — use 100.
function Read-Settings { param([string]$Path)
    if (Test-Path $Path) {
        return (Get-Content -Raw -Path $Path | ConvertFrom-Json -AsHashtable)
    }
    return @{}
}
function Write-Settings { param($Obj, [string]$Path)
    $Obj | ConvertTo-Json -Depth 100 | Set-Content -Path $Path -Encoding utf8
}

Write-Host 'embo dependencies'
Write-Host ''

# Python 3.8-3.12 — required by RLM. Report only; show winget command.
$py = if (Test-Cmd 'py') { 'py' } elseif (Test-Cmd 'python') { 'python' } else { $null }
if ($py) {
    $pv = & $py -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>$null
    Write-Host "  python: found ($pv)  [RLM needs 3.8-3.12; 3.13+ breaks ChromaDB]"
} else {
    Write-Host '  python: MISSING — required by RLM.'
    Write-Host '    winget install --id Python.Python.3.12 -e'
    $script:DepsMissing = $true
}

# Node.js 20+ — required by claude-mem. Report only.
if (Test-Cmd 'node') {
    $nv = (& node -v) -replace '^v',''
    $major = [int]($nv -split '\.')[0]
    if ($major -ge 20) {
        Write-Host "  node: found (v$nv)  [claude-mem needs 20+]"
    } else {
        Write-Host '  node: found but < 20 — claude-mem needs Node 20+. Upgrade Node.'
        $script:DepsMissing = $true
    }
} else {
    Write-Host '  node: MISSING — required by claude-mem.'
    Write-Host '    winget install --id OpenJS.NodeJS.LTS -e'
    $script:DepsMissing = $true
}

# bash — needed by the plugin's hooks; without it hooks silently drop prompts.
if (Test-Cmd 'bash') {
    Write-Host '  bash: found'
} else {
    Write-Host '  bash: MISSING — hooks need it. winget install --id Git.Git -e (includes Git Bash)'
    $script:DepsMissing = $true
}

# jq — required by the plugin's hooks at runtime. Offer winget install.
if (Test-Cmd 'jq') {
    Write-Host '  jq: found'
} elseif (Test-Cmd 'winget') {
    if (Confirm-Step '  jq missing. Install with winget? [Y/n] ' 'y') {
        winget install --id jqlang.jq -e --accept-package-agreements --accept-source-agreements
        Write-Host '  jq: install attempted (winget)'
    } else {
        Write-Host '  jq: MISSING — needed by hooks. winget install --id jqlang.jq -e'
        $script:DepsMissing = $true
    }
} else {
    Write-Host '  jq: MISSING and winget not found. Install manually: https://jqlang.org/download/'
    $script:DepsMissing = $true
}

# uv — claude-mem's Python package manager. Official script installer.
if (Test-Cmd 'uv') {
    Write-Host '  uv: found'
} else {
    if (Confirm-Step '  uv missing. Install via astral.sh installer? [Y/n] ' 'y') {
        powershell -ExecutionPolicy ByPass -c 'irm https://astral.sh/uv/install.ps1 | iex'
        Write-Host '  uv: installed to %USERPROFILE%\.local\bin (open a NEW shell for PATH)'
    } else {
        Write-Host '  uv: skipped — irm https://astral.sh/uv/install.ps1 | iex'
    }
}

# bun — claude-mem's JS runtime. Use the irm script (winget has a PATH bug).
if (Test-Cmd 'bun') {
    Write-Host '  bun: found'
} else {
    if (Confirm-Step '  bun missing. Install via bun.sh installer? [Y/n] ' 'y') {
        powershell -c 'irm bun.sh/install.ps1 | iex'
        Write-Host '  bun: installed to %USERPROFILE%\.bun\bin (open a NEW shell for PATH)'
    } else {
        Write-Host '  bun: skipped — powershell -c "irm bun.sh/install.ps1 | iex"'
    }
}

Write-Host ''

# ---------------------------------------------------------------------------
# Standalone mode: copy embo into ~/.claude/
# ---------------------------------------------------------------------------
if ($Standalone) {
    if (-not (Test-Path $Src)) {
        Write-Error "$Src not found. Run -Standalone from the embo repo root."
        exit 1
    }

    Write-Host "Standalone install: syncing from $Src to $Target"

    # 1. RLM script + bin wrapper (siblings so the wrapper resolves
    #    ..\rlm_scripts\rlm_repl.py relative to itself).
    New-Item -ItemType Directory -Force -Path (Join-Path $Target 'rlm_scripts'),(Join-Path $Target 'bin') | Out-Null
    Copy-Item (Join-Path $Src 'rlm_scripts\rlm_repl.py') (Join-Path $Target 'rlm_scripts\') -Force
    Copy-Item (Join-Path $Src 'bin\rlm_repl') (Join-Path $Target 'bin\') -Force
    Write-Host '  rlm: rlm_repl.py + bin/rlm_repl wrapper'

    # 2. Agents
    New-Item -ItemType Directory -Force -Path (Join-Path $Target 'agents') | Out-Null
    Copy-Item (Join-Path $Src 'agents\*.md') (Join-Path $Target 'agents\') -Force
    Write-Host '  agents: copied'

    # 3. Commands -> embo/ namespace dir (/embo:*); research/ subdir kept.
    New-Item -ItemType Directory -Force -Path (Join-Path $Target 'commands\embo') | Out-Null
    Copy-Item (Join-Path $Src 'commands\*') (Join-Path $Target 'commands\embo\') -Recurse -Force
    Write-Host '  commands: synced to commands/embo/ (/embo:*)'

    # 4. Profiles
    New-Item -ItemType Directory -Force -Path (Join-Path $Target 'profiles') | Out-Null
    Copy-Item (Join-Path $Src 'profiles\*.yaml') (Join-Path $Target 'profiles\') -Force
    Write-Host '  profiles: copied'

    # 5. Hooks (exclude *.test.sh)
    New-Item -ItemType Directory -Force -Path (Join-Path $Target 'hooks') | Out-Null
    Get-ChildItem (Join-Path $Src 'hooks\*.sh') |
        Where-Object { $_.Name -notlike '*.test.sh' } |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $Target 'hooks\') -Force }
    Write-Host '  hooks: copied'

    # 6. Statusline
    $sl = Join-Path $Src 'statusline.sh'
    if (Test-Path $sl) {
        Copy-Item $sl (Join-Path $Target 'statusline.sh') -Force
        Write-Host '  statusline: copied'
    }

    # 7. settings.json — register the 3 real hooks with literal ~/.claude/
    #    paths (a manual install has no ${CLAUDE_PLUGIN_ROOT}), set
    #    statusLine, add embo permissions. Idempotent on each piece.
    #    Skip hook registration when bash is absent: a registered .sh hook
    #    with no bash silently drops prompts in Claude Code.
    $settingsPath = Join-Path $Target 'settings.json'
    $s = Read-Settings $settingsPath
    if (-not $s.ContainsKey('hooks')) { $s['hooks'] = @{} }
    if (-not $s['hooks'].ContainsKey('UserPromptSubmit')) { $s['hooks']['UserPromptSubmit'] = @() }
    if (-not $s['hooks'].ContainsKey('PreToolUse')) { $s['hooks']['PreToolUse'] = @() }
    if (-not $s.ContainsKey('permissions')) { $s['permissions'] = @{} }
    if (-not $s['permissions'].ContainsKey('allow')) { $s['permissions']['allow'] = @() }

    function Test-HookCmd { param($Arr, [string]$Token)
        foreach ($g in $Arr) {
            foreach ($h in $g.hooks) { if ($h.command -like "*$Token*") { return $true } }
        }
        return $false
    }

    if (Test-Cmd 'bash') {
        if (-not (Test-HookCmd $s['hooks']['UserPromptSubmit'] 'context-guard.sh')) {
            $s['hooks']['UserPromptSubmit'] += @{ hooks = @(@{ type = 'command'; command = 'bash ~/.claude/hooks/context-guard.sh' }) }
            Write-Host '  settings.json: context-guard.sh registered'
        }
        if (-not (Test-HookCmd $s['hooks']['UserPromptSubmit'] 'behavioral-reminder.sh')) {
            $s['hooks']['UserPromptSubmit'] += @{ hooks = @(@{ type = 'command'; command = 'bash ~/.claude/hooks/behavioral-reminder.sh' }) }
            Write-Host '  settings.json: behavioral-reminder.sh registered'
        }
        if (-not (Test-HookCmd $s['hooks']['PreToolUse'] 'approve-compound.sh')) {
            $s['hooks']['PreToolUse'] += @{ matcher = 'Bash'; hooks = @(@{ type = 'command'; command = 'bash ~/.claude/hooks/approve-compound.sh' }) }
            Write-Host '  settings.json: approve-compound.sh registered'
        }
        if (-not $s['statusLine']) {
            $s['statusLine'] = @{ type = 'command'; command = '~/.claude/statusline.sh' }
            Write-Host '  settings.json: statusLine added'
        }
    } else {
        Write-Host '  settings.json: hooks NOT registered — bash missing (would drop prompts).'
        Write-Host '    Install Git Bash, then re-run, to enable hooks.'
    }

    $perms = @(
        'Bash(rlm_repl *)','Bash(find:*)','Bash(git log:*)','Bash(git diff:*)',
        'Bash(git status:*)','Bash(grep:*)','Bash(head:*)','Bash(basename:*)',
        'Bash(git rev-parse:*)','Bash(~/.claude/hooks/embo-capture.sh *)'
    )
    $added = 0
    foreach ($p in $perms) {
        if ($s['permissions']['allow'] -notcontains $p) { $s['permissions']['allow'] += $p; $added++ }
    }
    Write-Host "  permissions: $added read-only rule(s) added"

    Write-Settings $s $settingsPath
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if ($script:Skipped -gt 0) {
    Write-Host "  $($script:Skipped) prompt(s) skipped with default 'no' (-Force without -Yes)."
    Write-Host ''
}

Write-Host 'PATH: ensure these are on PATH (a NEW shell picks up winget/installer changes):'
Write-Host '    %USERPROFILE%\.local\bin    (uv)'
Write-Host '    %USERPROFILE%\.bun\bin      (bun)'
if ($Standalone) {
    Write-Host '    %USERPROFILE%\.claude\bin   (rlm_repl, standalone only)'
}
Write-Host ''

if ($Standalone) {
    Write-Host 'Standalone install done. Restart Claude Code, then /embo:init for a'
    Write-Host 'new project or /embo:start for a session. Verify with /embo:health.'
} else {
    Write-Host 'Dependencies done. Now install the plugins inside Claude Code:'
    Write-Host '    /plugin marketplace add povesma/embo  then  /plugin install embo@embo'
    Write-Host '    /plugin install claude-mem   (from thedotmack/claude-mem)'
    Write-Host 'Then verify with /embo:health.'
}

if ($script:DepsMissing) {
    Write-Host ''
    Write-Host 'WARNING: one or more required dependencies are missing (see above).'
    exit 1
}
