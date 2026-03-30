#!/bin/bash
# =============================================================================
# Container Entrypoint — Claude Code Dev Environment
# Handles: NVM init, SSH agent, Claude auth, Docker group, runtime checks
# =============================================================================

set -e

# -- Colors for output --
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Docker Claude — Development Environment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# -- NVM --
export NVM_DIR="/usr/local/nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    echo -e "${GREEN}✓${NC} Node.js $(node --version 2>/dev/null || echo 'not loaded')"
fi

# -- .NET --
if [ -x "/usr/local/dotnet/dotnet" ]; then
    export PATH="/usr/local/dotnet:$PATH"
    echo -e "${GREEN}✓${NC} .NET $(/usr/local/dotnet/dotnet --version 2>/dev/null || echo 'installed')"
fi

# -- Go --
if [ -d "/usr/local/go" ]; then
    export PATH="/usr/local/go/bin:/home/dev/go/bin:$PATH"
    export GOPATH="/home/dev/go"
    mkdir -p "$GOPATH"
    echo -e "${GREEN}✓${NC} Go $(go version 2>/dev/null | awk '{print $3}' || echo 'installed')"
fi

# -- Rust --
if [ -d "/usr/local/cargo" ]; then
    export PATH="/usr/local/cargo/bin:$PATH"
    echo -e "${GREEN}✓${NC} Rust $(rustc --version 2>/dev/null | awk '{print $2}' || echo 'installed')"
fi

# -- Solana (if available) --
if [ -d "/home/dev/.local/share/solana/install/active_release" ]; then
    export PATH="/home/dev/.local/share/solana/install/active_release/bin:$PATH"
    echo -e "${GREEN}✓${NC} Solana $(solana --version 2>/dev/null | awk '{print $2}' || echo 'installed')"
fi

# -- Flutter (if available) --
if [ -d "/opt/flutter" ]; then
    export PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH"
    echo -e "${GREEN}✓${NC} Flutter $(flutter --version 2>/dev/null | head -1 | awk '{print $2}' || echo 'installed')"
fi

# -- SSH Agent Forwarding --
if [ -S "/ssh-agent" ]; then
    export SSH_AUTH_SOCK=/ssh-agent
    echo -e "${GREEN}✓${NC} SSH agent forwarded"
elif [ -d "/home/dev/.ssh" ] && [ "$(ls -A /home/dev/.ssh 2>/dev/null)" ]; then
    # Windows mode: keys mounted directly, start a local agent
    eval "$(ssh-agent -s)" > /dev/null 2>&1
    for key in /home/dev/.ssh/id_*; do
        [ -f "$key" ] && [[ "$key" != *.pub ]] && ssh-add "$key" 2>/dev/null || true
    done
    echo -e "${GREEN}✓${NC} SSH keys loaded from mounted directory"
else
    echo -e "${YELLOW}!${NC} No SSH agent or keys detected"
fi

# -- Docker socket --
if [ -S "/var/run/docker.sock" ]; then
    echo -e "${GREEN}✓${NC} Docker socket available ($(docker --version 2>/dev/null | awk '{print $3}' | tr -d ','))"
else
    echo -e "${YELLOW}!${NC} Docker socket not mounted (default for security)"
    echo -e "    To enable DinD: ${BLUE}make DIND=true up${NC}"
fi

# -- Claude Code Auth --
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "${GREEN}✓${NC} Claude Code: API key configured"
elif [ -f "/home/dev/.claude/credentials.json" ] || [ -f "/home/dev/.claude/.credentials.json" ]; then
    echo -e "${GREEN}✓${NC} Claude Code: OAuth session found"
else
    echo -e "${YELLOW}!${NC} Claude Code: No auth configured"
    echo -e "    Set ANTHROPIC_API_KEY or run: ${BLUE}claude login${NC}"
fi

# -- Claude Code Settings --
if [ -f "/etc/claude-code/settings.json" ]; then
    # Symlink mounted settings into Claude Code's expected location
    ln -sf /etc/claude-code/settings.json /home/dev/.claude/settings.json 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Claude Code: Global settings loaded"
else
    echo -e "${YELLOW}!${NC} Claude Code: No global settings (using defaults)"
fi

# -- Workspace --
echo ""
if [ "$(ls -A /workspace 2>/dev/null)" ]; then
    PROJECT_COUNT=$(find /workspace -maxdepth 1 -mindepth 1 -type d | wc -l)
    echo -e "${GREEN}✓${NC} Workspace: ${PROJECT_COUNT} project(s) in /workspace"
else
    echo -e "${YELLOW}!${NC} Workspace is empty. Get started:"
    echo -e "    ${BLUE}cd /workspace && git clone <your-repo>${NC}"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# -- Execute command --
exec "$@"
