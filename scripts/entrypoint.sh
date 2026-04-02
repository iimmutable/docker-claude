#!/bin/bash
# =============================================================================
# Container Entrypoint — Claude Code Dev Environment
# Handles: Permission fix, NVM init, SSH agent, Claude auth, runtime checks
#
# This script runs twice:
#   1st pass: As root (UID 0) — fixes permissions, then drops to dev
#   2nd pass: As dev (UID 1000) — continues normal startup
# =============================================================================

set -e

# -- Colors for output --
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# =============================================================================
# ROOT MODE: Fix permissions then drop to dev
# =============================================================================
if [ "$(id -u)" = "0" ]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Docker Claude — Initializing (as root)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Fix files copied from host (common macOS UIDs: 501, 502)
    echo -e "${YELLOW}!${NC} Fixing file ownership for host-copied files..."
    find /workspace -type f -o -type d 2>/dev/null | while read item; do
        uid=$(stat -c "%u" "$item" 2>/dev/null || echo "")
        # Fix files owned by common host UIDs (501, 502) or with no owner
        if [ "$uid" = "501" ] || [ "$uid" = "502" ] || [ "$uid" = "" ]; then
            chown -h dev:dev "$item" 2>/dev/null || true
        fi
    done

    # Also fix orphaned files (nouser)
    find /workspace -nouser 2>/dev/null -exec chown -h dev:dev {} \; || true

    # Fix home directory if needed
    find /home/dev -type f -o -type d 2>/dev/null | while read item; do
        uid=$(stat -c "%u" "$item" 2>/dev/null || echo "")
        if [ "$uid" = "501" ] || [ "$uid" = "502" ] || [ "$uid" = "" ]; then
            chown -h dev:dev "$item" 2>/dev/null || true
        fi
    done
    find /home/dev -nouser 2>/dev/null -exec chown -h dev:dev {} \; || true

    echo -e "${GREEN}✓${NC} Ownership fixed"

    # Drop privileges and re-execute as dev user
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exec gosu dev "$0" "$@"
fi

# =============================================================================
# DEV USER MODE: Normal startup (runs as UID 1000)
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Claude Code Development Environment${NC}"
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
    export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
    export GOPATH="$HOME/go"
    mkdir -p "$GOPATH"
    echo -e "${GREEN}✓${NC} Go $(go version 2>/dev/null | awk '{print $3}' || echo 'installed')"
fi

# -- Rust --
if [ -d "/usr/local/cargo" ]; then
    export PATH="/usr/local/cargo/bin:$PATH"
    echo -e "${GREEN}✓${NC} Rust $(rustc --version 2>/dev/null | awk '{print $2}' || echo 'installed')"
fi

# -- Solana (if available) --
if [ -d "$HOME/.local/share/solana/install/active_release" ]; then
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
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
elif [ -d "$HOME/.ssh" ] && [ "$(ls -A "$HOME/.ssh" 2>/dev/null)" ]; then
    # Windows mode: keys mounted directly, start a local agent
    eval "$(ssh-agent -s)" > /dev/null 2>&1
    for key in "$HOME"/.ssh/id_*; do
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
    echo -e "${YELLOW}!${NC} Docker socket not mounted — DinD unavailable"
fi

# -- Claude Code Auth --
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "${GREEN}✓${NC} Claude Code: API key configured"
elif [ -f "$HOME/.claude/credentials.json" ] || [ -f "$HOME/.claude/.credentials.json" ]; then
    echo -e "${GREEN}✓${NC} Claude Code: OAuth session found"
else
    echo -e "${YELLOW}!${NC} Claude Code: No auth configured"
    echo -e "    Set ANTHROPIC_API_KEY or run: ${BLUE}claude login${NC}"
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
