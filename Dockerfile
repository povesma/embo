FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl git python3 jq nodejs npm unzip tmux && \
    npm install -g @anthropic-ai/claude-code && \
    curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    ln -s /root/.bun/bin/bunx /usr/local/bin/bunx && \
    curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ln -s /root/.local/bin/uv /usr/local/bin/uv && \
    ln -s /root/.local/bin/uvx /usr/local/bin/uvx && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Pre-cache chroma-mcp with Python 3.12 (3.13+ has chromadb compat issues)
RUN uvx --python 3.12 chroma-mcp --help >/dev/null 2>&1 || true

WORKDIR /workspace
COPY . /workspace/

# Install to a staging dir, then copy at runtime
RUN mkdir -p /opt/rlm-mem && \
    TARGET=/opt/rlm-mem bash -c ' \
    mkdir -p "$TARGET/agents" && \
    cp .claude/agents/*.md "$TARGET/agents/" && \
    mkdir -p "$TARGET/commands/dev" && \
    cp -r .claude/commands/dev/* "$TARGET/commands/dev/" && \
    mkdir -p "$TARGET/profiles" && \
    cp .claude/profiles/*.yaml "$TARGET/profiles/" && \
    mkdir -p "$TARGET/hooks" && \
    cp .claude/hooks/*.sh "$TARGET/hooks/" && \
    chmod +x "$TARGET/hooks/"*.sh && \
    mkdir -p "$TARGET/rlm_scripts" && \
    cp .claude/rlm_scripts/*.py "$TARGET/rlm_scripts/" && \
    cp .claude/statusline.sh "$TARGET/statusline.sh" && \
    chmod +x "$TARGET/statusline.sh" \
    '

# Copy staged files into ~/.claude at container start
# (VOLUME mount happens after build, so we copy at runtime)
COPY <<'ENTRYPOINT' /entrypoint.sh
#!/bin/bash
cp -rn /opt/rlm-mem/* /root/.claude/ 2>/dev/null || true

# Restore .claude.json from backup if missing (Claude Code requires it)
if [ ! -f /root/.claude.json ]; then
  backup=$(ls -t /root/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
  if [ -n "$backup" ]; then
    cp "$backup" /root/.claude.json
  else
    echo '{}' > /root/.claude.json
  fi
fi

# Install claude-mem plugin if not already installed
if [ ! -f /root/.claude/plugins/installed_plugins.json ] || ! grep -q 'claude-mem' /root/.claude/plugins/installed_plugins.json 2>/dev/null; then
  echo "Installing claude-mem plugin..."
  claude plugin marketplace add thedotmack/claude-mem 2>/dev/null || true
  claude plugin install claude-mem@thedotmack --scope user 2>/dev/null || true
fi

# Ensure claude-mem uses Python 3.12 (chromadb breaks on 3.13+)
mkdir -p /root/.claude-mem
if [ ! -f /root/.claude-mem/settings.json ]; then
  echo '{"CLAUDE_MEM_PYTHON_VERSION":"3.12","CLAUDE_MEM_CHROMA_ENABLED":"false"}' > /root/.claude-mem/settings.json
else
  python3 -c "
import json
with open('/root/.claude-mem/settings.json') as f: s=json.load(f)
s['CLAUDE_MEM_PYTHON_VERSION']='3.12'
s['CLAUDE_MEM_CHROMA_ENABLED']='false'
with open('/root/.claude-mem/settings.json','w') as f: json.dump(s,f,indent=2)
" 2>/dev/null || true
fi

# Run smart-install to cache dependencies
PLUGIN_ROOT=$(find /root/.claude/plugins/cache/thedotmack/claude-mem -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)
if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/scripts/smart-install.js" ]; then
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  node "$PLUGIN_ROOT/scripts/smart-install.js" 2>/dev/null || true
fi

exec "$@"
ENTRYPOINT
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["claude"]
