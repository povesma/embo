<#
.SYNOPSIS
  Remove a MANUAL embo install from ~/.claude/ on Windows, any era.
  PowerShell parity with uninstall.sh.

.DESCRIPTION
  Covers both manual-install layouts:
    - current  (install.ps1 -Standalone): commands/embo/ (/embo:*),
      agents, hooks, bin/rlm_repl + rlm_scripts/rlm_repl.py, statusline,
      and the Bash(rlm_repl *) permission rule.
    - pre-plugin era (old install.ps1): commands/dev/ (/dev:*) and the old
      Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*) permission rule.
  Removes the shared pieces and the era-specific pieces of whichever is
  present. Backs up settings.json before editing.

  Does NOT touch:
    - the embo PLUGIN — remove that with /plugin uninstall embo@embo
      (Claude Code's own tool); this script is for manual installs only
    - claude-mem, bun, uv, node, jq, python (system dependencies)
    - ~/.claude/active-profile.yaml or ~/.claude/profiles/ (user-managed)
    - per-project .claude/rlm_state/ (local index state)

  Run with:  powershell -ExecutionPolicy Bypass -File uninstall.ps1

.PARAMETER Force
  Non-interactive; default answer 'no' (nothing removed).
.PARAMETER Yes
  With -Force, accept all removals.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$Target = Join-Path $env:USERPROFILE '.claude'
$SettingsPath = Join-Path $Target 'settings.json'

function Confirm-Step {
    param([string]$Prompt, [string]$Default = 'n')
    if ($Force) { if ($Yes) { return $true } else { return $false } }
    $ans = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($ans)) { $ans = $Default }
    return $ans -match '^[Yy]'
}

# Confirm, then remove a path (file or dir) if present.
function Remove-Target {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { Write-Host "  ${Label}: not present — skipping"; return }
    if (Confirm-Step "  Remove $Label ($Path)? [Y/n] " 'y') {
        Remove-Item -Recurse -Force $Path
        Write-Host "  ${Label}: removed"
    } else {
        Write-Host "  ${Label}: kept"
    }
}

Write-Host "Removing manual embo install from $Target"
Write-Host ''

# --- Files -----------------------------------------------------------------
Remove-Target (Join-Path $Target 'commands\embo')                 'embo commands (/embo:*)'
Remove-Target (Join-Path $Target 'commands\dev')                  'pre-plugin commands (/dev:*)'
Remove-Target (Join-Path $Target 'agents\rlm-subcall.md')         'agent rlm-subcall'
Remove-Target (Join-Path $Target 'agents\examine-advisor.md')     'agent examine-advisor'
Remove-Target (Join-Path $Target 'agents\approach-validator.md')  'agent approach-validator'
Remove-Target (Join-Path $Target 'bin\rlm_repl')                  'rlm_repl wrapper'
Remove-Target (Join-Path $Target 'rlm_scripts\rlm_repl.py')       'RLM script'
Remove-Target (Join-Path $Target 'hooks\context-guard.sh')        'hook context-guard'
Remove-Target (Join-Path $Target 'hooks\behavioral-reminder.sh')  'hook behavioral-reminder'
Remove-Target (Join-Path $Target 'hooks\approve-compound.sh')     'hook approve-compound'
Remove-Target (Join-Path $Target 'hooks\embo-capture.sh')         'hook embo-capture (helper)'
Remove-Target (Join-Path $Target 'hooks\fix-hooks.sh')            'hook fix-hooks (doctor)'
Remove-Target (Join-Path $Target 'hooks\docs-first-guard.sh')     'hook docs-first-guard (pre-plugin, deprecated)'
Remove-Target (Join-Path $Target 'statusline.sh')                 'statusline'

Write-Host ''

# --- settings.json ---------------------------------------------------------
# Strip embo hook registrations, the embo statusLine, and embo-specific
# permission rules. Keep non-embo entries. Backup first.
if (-not (Test-Path $SettingsPath)) {
    Write-Host '  settings.json: not present — nothing to clean'
} elseif (-not (Confirm-Step "  Clean embo entries from $SettingsPath? [Y/n] " 'y')) {
    Write-Host '  settings.json: left unchanged'
} else {
    Copy-Item $SettingsPath "$SettingsPath.embo-backup" -Force
    Write-Host "  settings.json: backed up to $SettingsPath.embo-backup"

    $s = Get-Content -Raw -Path $SettingsPath | ConvertFrom-Json -AsHashtable
    $emboHookRe = 'context-guard\.sh|behavioral-reminder\.sh|approve-compound\.sh'

    if ($s.ContainsKey('hooks') -and $s['hooks']) {
        foreach ($event in @($s['hooks'].Keys)) {
            $groups = @($s['hooks'][$event])
            $kept = @()
            foreach ($g in $groups) {
                # Drop inner hooks whose command references an embo hook script.
                $innerKept = @($g.hooks | Where-Object { $_.command -notmatch $emboHookRe })
                if ($innerKept.Count -gt 0) {
                    $g.hooks = $innerKept
                    $kept += $g
                }
            }
            if ($kept.Count -gt 0) { $s['hooks'][$event] = $kept }
            else { $s['hooks'].Remove($event) | Out-Null }
        }
    }

    # Drop the embo statusLine.
    if ($s.ContainsKey('statusLine') -and $s['statusLine'] -and
        ($s['statusLine'].command -match 'statusline\.sh')) {
        $s.Remove('statusLine') | Out-Null
    }

    # Drop embo-specific permission rules (current + pre-plugin); keep generics.
    if ($s.ContainsKey('permissions') -and $s['permissions'] -and $s['permissions'].ContainsKey('allow')) {
        $drop = @(
            'Bash(rlm_repl *)',
            'Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)',
            'Bash(~/.claude/hooks/embo-capture.sh *)'
        )
        $s['permissions']['allow'] = @($s['permissions']['allow'] | Where-Object { $drop -notcontains $_ })
    }

    $s | ConvertTo-Json -Depth 100 | Set-Content -Path $SettingsPath -Encoding utf8
    Write-Host '  settings.json: embo hooks, statusLine, and permission rules removed'
}

Write-Host ''
Write-Host 'Done. Restart Claude Code. Kept: profiles, active-profile.yaml,'
Write-Host 'claude-mem, and system dependencies (bun/uv/node/jq/python).'
Write-Host 'If you also installed the embo plugin: /plugin uninstall embo@embo.'
