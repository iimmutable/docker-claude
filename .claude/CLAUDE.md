# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dockerized development environment running Claude Code CLI inside Docker. Provides Node.js, .NET, Go, Rust runtimes with optional Solana and Mobile profiles. Named volumes store code and auth persistently.

## Commands

```bash
make build              # Build core image (Node + .NET + Go + Rust)
make build-slim         # Build with Node + Go only (skip .NET, Rust)
make build-all          # Build all profiles including Solana + Mobile
make build-no-cache     # Full rebuild without layer cache
make GPU=true build     # Build with NVIDIA CUDA support (Linux/WSL2 only)

make up                 # Start core environment
make down               # Stop all services (volumes persist)
make solana-up          # Start with Solana profile
make mobile-up          # Start with Mobile profile
make all-up             # Start everything

make shell              # Open bash in docker-claude
make claude             # Launch Claude Code CLI
make login              # Run Claude OAuth login flow
make shell-solana       # Shell in Solana container
make shell-mobile       # Shell in Mobile container

make health             # Verify all runtimes, auth, Docker socket
make status             # Show containers, volumes, image sizes

make clean              # Remove containers + images (volumes persist)
make nuke               # Remove EVERYTHING including volumes (prompts)

make backup             # Backup project volume to ./backups/
make restore FILE=...   # Restore from backup (stops containers)
```

## Architecture

### Conditional Runtime Installation

The Dockerfile uses build args to conditionally install runtimes:

```dockerfile
ARG INCLUDE_NODE=true
ARG INCLUDE_DOTNET=true
ARG INCLUDE_GOLANG=true
ARG INCLUDE_RUST=true
```

Each runtime block checks its arg before installing. This allows slim builds via:
```bash
docker compose build --build-arg INCLUDE_DOTNET=false --build-arg INCLUDE_RUST=false
```

### Volume Architecture

Two named volumes (fully virtualized, no host bind mounts):
- `claude-projects` → `/workspace` — code, dependencies, caches
- `claude-auth` → `/home/dev/.claude` — OAuth credentials

Files enter/exit via:
- `git clone` inside container
- `docker cp` for ad-hoc transfers
- Backup tarball exports (`make backup`)

### Profile System

Optional profiles extend the base image:
- `--profile solana` → Dockerfile.solana (Solana CLI + Anchor + Rust BPF target)
- `--profile mobile` → Dockerfile.mobile (Android SDK + Flutter + React Native CLI)

Both inherit from `docker-claude:latest` via `ARG BASE_IMAGE=docker-claude`.

### Port Convention

All host ports use 41xxx offset to avoid conflicts:
- Container 3000 → Host 41300 (React/Express)
- Container 5173 → Host 41517 (Vite)
- Container 8080 → Host 41808 (Go/Generic)

Map defined in docker-compose.yml `ports:` section.

### Entrypoint Logic

`entrypoint.sh` handles:
1. NVM initialization (sources `/usr/local/nvm/nvm.sh`)
2. SSH agent forwarding (Mac: socket mount; Windows: key mount + local agent)
3. Claude auth detection (API key or OAuth credentials)
4. Runtime status display

All shells must source NVM first for Node commands:
```bash
. /usr/local/nvm/nvm.sh
```

## Key Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Core image with conditional runtime build args |
| `docker-compose.yml` | Service definitions, volumes, ports, profiles |
| `Makefile` | Primary interface — all commands via `make` |
| `entrypoint.sh` | Container startup: runtime init, auth check |
| `config/.bashrc` | Shell config inside container (aliases, PATH) |
| `devcontainer.json` | VS Code Dev Container integration |
| `Dockerfile.solana` | Solana profile (extends base) |
| `Dockerfile.mobile` | Mobile profile (Android + Flutter + RN) |

## Modifying the Image

When adding new runtime or tool:

1. Add build arg in Dockerfile: `ARG INCLUDE_NEW=true`
2. Add conditional install block following existing pattern
3. Add PATH/env setup in Dockerfile `ENV` section
4. Update `config/.bashrc` with conditional PATH export
5. Update `entrypoint.sh` runtime status display
6. Update `devcontainer.json` extensions if VS Code relevant
7. Update README.md documentation

## Cross-Platform Notes

- Mac: SSH agent forwarding via `SSH_AUTH_SOCK` mount
- Windows: Keys mounted from `%USERPROFILE%\.ssh`, entrypoint starts local agent
- GPU: Only works on Linux/WSL2 (not macOS)
- Line endings: `.gitattributes` enforces LF, setup scripts sanitize CRLF