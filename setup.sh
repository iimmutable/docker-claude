#!/bin/bash
# =============================================================================
# setup.sh — One-command setup for Claude Code Dev Environment (Mac/Linux)
#
# Usage:
#   ./scripts/setup.sh                    # Full build, all stacks
#   ./scripts/setup.sh --slim             # Node + Go only
#   ./scripts/setup.sh --with-solana      # Include Solana profile
#   ./scripts/setup.sh --with-mobile      # Include Mobile profile
#   ./scripts/setup.sh --with-gpu         # Include NVIDIA GPU support
#   ./scripts/setup.sh --all              # Everything including all profiles
# =============================================================================

set -euo pipefail

# -- Colors --
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     Claude Code Dev Environment — Setup                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# -- Parse arguments --
INCLUDE_NODE=true
INCLUDE_DOTNET=true
INCLUDE_GOLANG=true
INCLUDE_RUST=true
INCLUDE_GPU=false
WITH_SOLANA=false
WITH_MOBILE=false

for arg in "$@"; do
    case $arg in
        --slim)
            INCLUDE_DOTNET=false
            INCLUDE_RUST=false
            echo -e "${YELLOW}Slim mode: Node + Go only${NC}"
            ;;
        --with-solana)
            WITH_SOLANA=true
            echo -e "${BLUE}Including Solana profile${NC}"
            ;;
        --with-mobile)
            WITH_MOBILE=true
            echo -e "${BLUE}Including Mobile profile${NC}"
            ;;
        --with-gpu)
            INCLUDE_GPU=true
            echo -e "${BLUE}Including GPU/CUDA support${NC}"
            ;;
        --all)
            WITH_SOLANA=true
            WITH_MOBILE=true
            echo -e "${BLUE}Building everything${NC}"
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --slim           Build with Node + Go only (skip .NET, Rust)"
            echo "  --with-solana    Build and start the Solana profile"
            echo "  --with-mobile    Build and start the Mobile profile"
            echo "  --with-gpu       Enable NVIDIA GPU support"
            echo "  --all            Build everything (all profiles)"
            echo "  --help           Show this help"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${NC}"
            exit 1
            ;;
    esac
done

# -- Preflight checks --
echo -e "\n${BLUE}[1/6] Preflight checks...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found. Install Docker Desktop first.${NC}"
    echo "  → https://docs.docker.com/desktop/"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker $(docker --version | awk '{print $3}' | tr -d ',')"

if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}✗ Docker daemon not running. Start Docker Desktop.${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker daemon running"

if ! docker compose version > /dev/null 2>&1; then
    echo -e "${RED}✗ Docker Compose not found.${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker Compose $(docker compose version --short)"

# -- Sanitize scripts (fix permissions + line endings from download) --
echo -e "\n${BLUE}[1.5/6] Sanitizing scripts...${NC}"
find "$PROJECT_DIR/scripts" -type f \( -name "*.sh" \) -exec chmod +x {} \;
find "$PROJECT_DIR/scripts" -type f \( -name "*.sh" \) -exec sed -i '' 's/\r$//' {} \; 2>/dev/null \
    || find "$PROJECT_DIR/scripts" -type f \( -name "*.sh" \) -exec sed -i 's/\r$//' {} \;
find "$PROJECT_DIR/config" -type f -exec sed -i '' 's/\r$//' {} \; 2>/dev/null \
    || find "$PROJECT_DIR/config" -type f -exec sed -i 's/\r$//' {} \;
# Also sanitize Dockerfiles
find "$PROJECT_DIR" -maxdepth 1 -name "Dockerfile*" -exec sed -i '' 's/\r$//' {} \; 2>/dev/null \
    || find "$PROJECT_DIR" -maxdepth 1 -name "Dockerfile*" -exec sed -i 's/\r$//' {} \;
echo -e "${GREEN}✓${NC} Scripts sanitized (permissions + line endings)"

# -- Create .env file --
echo -e "\n${BLUE}[2/6] Configuring environment...${NC}"

if [ ! -f .env ]; then
    cat > .env <<EOF
# Claude Code API Key (leave empty for OAuth login)
ANTHROPIC_API_KEY=

# SSH Agent (auto-detected on Mac/Linux)
SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-}

# Host user home (for .gitconfig mount)
HOME=${HOME}
EOF
    echo -e "${GREEN}✓${NC} Created .env file"
    echo -e "${YELLOW}  → Edit .env to add your ANTHROPIC_API_KEY (or use 'claude login' later)${NC}"
else
    echo -e "${GREEN}✓${NC} .env file already exists"
fi

# -- Build core image --
echo -e "\n${BLUE}[3/6] Building core image...${NC}"
echo -e "  Stacks: Node=${INCLUDE_NODE} .NET=${INCLUDE_DOTNET} Go=${INCLUDE_GOLANG} Rust=${INCLUDE_RUST} GPU=${INCLUDE_GPU}"

docker compose build \
    --build-arg INCLUDE_NODE=${INCLUDE_NODE} \
    --build-arg INCLUDE_DOTNET=${INCLUDE_DOTNET} \
    --build-arg INCLUDE_GOLANG=${INCLUDE_GOLANG} \
    --build-arg INCLUDE_RUST=${INCLUDE_RUST} \
    --build-arg INCLUDE_GPU=${INCLUDE_GPU} \
    claude-dev

echo -e "${GREEN}✓${NC} Core image built"

# -- Build profile images --
echo -e "\n${BLUE}[4/6] Building profile images...${NC}"

if [ "$WITH_SOLANA" = true ]; then
    docker compose --profile solana build claude-solana
    echo -e "${GREEN}✓${NC} Solana image built"
else
    echo -e "${YELLOW}–${NC} Solana skipped (use --with-solana to include)"
fi

if [ "$WITH_MOBILE" = true ]; then
    docker compose --profile mobile build claude-mobile
    echo -e "${GREEN}✓${NC} Mobile image built"
else
    echo -e "${YELLOW}–${NC} Mobile skipped (use --with-mobile to include)"
fi

# -- Create volumes --
echo -e "\n${BLUE}[5/6] Creating volumes...${NC}"
docker volume create claude-projects 2>/dev/null || true
docker volume create claude-auth 2>/dev/null || true
echo -e "${GREEN}✓${NC} Volumes ready"

# -- Start services --
echo -e "\n${BLUE}[6/6] Starting services...${NC}"

COMPOSE_PROFILES=""
if [ "$WITH_SOLANA" = true ]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES:+$COMPOSE_PROFILES,}solana"
fi
if [ "$WITH_MOBILE" = true ]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES:+$COMPOSE_PROFILES,}mobile"
fi

if [ -n "$COMPOSE_PROFILES" ]; then
    COMPOSE_PROFILES="--profile $(echo $COMPOSE_PROFILES | tr ',' ' --profile ')"
fi

eval docker compose $COMPOSE_PROFILES up -d

echo -e "\n${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✓ Setup complete!                                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "Quick start:"
echo -e "  ${BLUE}docker compose exec claude-dev bash${NC}          # Open shell"
echo -e "  ${BLUE}docker compose exec claude-dev claude${NC}        # Start Claude Code"
echo -e "  ${BLUE}docker compose exec claude-dev claude login${NC}  # OAuth login"
echo ""
echo -e "Manage:"
echo -e "  ${BLUE}docker compose down${NC}                          # Stop (volumes persist)"
echo -e "  ${BLUE}docker compose down -v${NC}                       # Stop + delete volumes"
echo -e "  ${BLUE}docker compose logs -f claude-dev${NC}             # View logs"
echo ""
