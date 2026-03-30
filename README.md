# Docker Claude — Dockerized Development Environment

A fully virtualized, cross-platform development environment running Claude Code inside Docker. Supports TypeScript/JavaScript, Node.js, Express, React, React Native, Vue 3, ASP.NET Core, C#, Go, Rust, Solana, Flutter, and more.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     Docker Compose                           │
│                                                              │
│  SERVICES                                                    │
│  ├── docker-claude          (default)  Core dev environment  │
│  ├── docker-claude-solana   (profile)  Solana + Anchor       │
│  └── docker-claude-mobile   (profile)  Android SDK/Flutter/RN│
│                                                              │
│  VOLUMES                                                     │
│  ├── claude-projects  →  /workspace  (code + deps + caches) │
│  └── claude-auth      →  ~/.claude   (auth persistence)     │
│                                                              │
│  IMAGE (conditional install via build args)                   │
│  Ubuntu 24.04 LTS base + Docker CLI + core utils             │
│  + nvm + Node LTS + pnpm/yarn/tsx          (INCLUDE_NODE)    │
│  + .NET 8 & 9 SDK                          (INCLUDE_DOTNET)  │
│  + Go 1.23 + gopls + delve                 (INCLUDE_GOLANG)  │
│  + rustup + stable + rust-analyzer/clippy  (INCLUDE_RUST)    │
│  + NVIDIA CUDA 12.4 runtime                (INCLUDE_GPU)     │
│  + Claude Code CLI + non-root user + SSH/Git                 │
└──────────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Docker Desktop** installed and running
  - Mac: [Download](https://docs.docker.com/desktop/install/mac-install/) — choose Apple Silicon (M-series) or Intel
  - Windows: [Download](https://docs.docker.com/desktop/install/windows-install/) — requires WSL2 backend
- **make** (pre-installed on Mac; Windows: install via `choco install make` or use scripts directly)

To check your Mac chip: `uname -m` → `arm64` = Apple Silicon, `x86_64` = Intel.

## Quick Start

### Mac / Linux

```bash
cd docker-claude
cp .env.example .env          # Edit: add your ANTHROPIC_API_KEY
chmod +x scripts/setup.sh scripts/entrypoint.sh
make build                    # First build takes ~10-20 min
make up
make health                   # Verify all runtimes
make claude                   # Launch Claude Code
```

### Windows (PowerShell)

```powershell
cd docker-claude
copy .env.example .env        # Edit: add your ANTHROPIC_API_KEY
.\scripts\setup.ps1
```

## Makefile Commands

The Makefile is the primary interface. Run `make help` to see all commands:

```bash
# Build
make build              # Build core image (all stacks)
make build-slim         # Build with Node + Go only (skip .NET, Rust)
make build-all          # Build everything including Solana + Mobile profiles
make build-no-cache     # Full rebuild without Docker layer cache
make GPU=true build     # Build with NVIDIA GPU support

# Run
make up                 # Start core environment
make down               # Stop all services (volumes persist)
make restart            # Stop + start
make solana-up          # Start with Solana profile
make mobile-up          # Start with Mobile profile
make all-up             # Start everything

# Interactive
make shell              # Open bash shell in docker-claude
make claude             # Launch Claude Code CLI
make login              # Run Claude OAuth login
make shell-solana       # Open shell in Solana container
make shell-mobile       # Open shell in Mobile container

# Diagnostics
make health             # Check all runtimes, auth, Docker socket
make status             # Show containers, volumes, image sizes
make logs               # Follow docker-claude logs
make logs-all           # Follow all service logs

# Cleanup
make clean              # Remove containers + images (volumes persist)
make nuke               # ⚠️ Remove EVERYTHING including volumes

# Backup & Restore
make backup             # Backup project volume to timestamped tar.gz
make backup-enc         # Encrypted backup (AES-256, prompts for passphrase)
make backup-list        # List all backups (plain + encrypted)
make restore FILE=...   # Restore from a plain backup
make restore-enc FILE=... # Restore from an encrypted backup
make backup-clean       # Delete backups older than 30 days

# Security Overrides
make DIND=true up       # Enable Docker-in-Docker (mounts Docker socket)
make DEBUG=true up      # Enable debugger support (SYS_PTRACE + unconfined seccomp)
make DIND=true DEBUG=true up  # Both
```

## Setup Options

When using the setup scripts directly (instead of `make`):

| Flag (bash) | Flag (PowerShell) | Effect |
|---|---|---|
| `--slim` | `-Slim` | Build Node + Go only (skip .NET, Rust) |
| `--with-solana` | `-WithSolana` | Include Solana/Anchor profile |
| `--with-mobile` | `-WithMobile` | Include Android SDK + Flutter + RN |
| `--with-gpu` | `-WithGpu` | Include NVIDIA CUDA runtime |
| `--all` | `-All` | Build everything |

```bash
./scripts/setup.sh --slim             # Lightweight build
./scripts/setup.sh --with-solana      # Include Solana
./scripts/setup.sh --all --with-gpu   # Everything + GPU
```

## Authentication

### Option A: API Key

Add to your `.env` file:

```
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
```

Then restart: `make down && make up`

### Option B: OAuth (interactive)

```bash
make login
```

OAuth tokens are persisted in the `claude-auth` volume — you only need to login once.

## Claude Code Configuration

Claude Code uses a hierarchical settings system. Docker Claude mounts a global `settings.json` into the container and supports per-project overrides.

### Settings Hierarchy (highest priority wins)

```
Per-project    /workspace/my-project/.claude/settings.json      (team, checked into git)
Per-project    /workspace/my-project/.claude/settings.local.json (personal, git-ignored)
Global         ~/.claude/settings.json                           (mounted from config/)
```

### Global Settings

Edit `config/claude-settings.json` on your host to change global defaults. This file is mounted read-only into the container and symlinked to `~/.claude/settings.json` at startup. Changes take effect on next container restart.

The default config sets:

- **Model** — defaults to Opus
- **Environment** — model mappings for Haiku/Sonnet/Opus, API timeout, telemetry disabled
- **Attribution** — header disabled

### Per-Project Settings

Inside the container, create project-level settings that override globals:

```bash
make shell
cd /workspace/my-project
mkdir -p .claude
cat > .claude/settings.json << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(npm test:*)",
      "Bash(npm run:*)"
    ]
  }
}
EOF
```

An example project settings file is at `config/claude-project-settings.example.json`.

### Personal Project Settings (git-ignored)

For personal tweaks within a project that shouldn't be shared with your team:

```bash
cat > .claude/settings.local.json << 'EOF'
{
  "preferences": {
    "thinking": "always"
  }
}
EOF
```

### Local Plugin Marketplace

You can mount a local Claude Code plugin marketplace from your host into the container.

**1. Set the path in `.env`:**

```
CLAUDE_MARKETPLACE_PATH=/Users/yourname/path/to/your/marketplace
```

**2. Restart:**

```bash
make down && make up
```

**3. Register inside the container:**

```bash
make shell
claude plugin marketplace add /etc/claude-code/marketplace
```

The marketplace is mounted read-only at `/etc/claude-code/marketplace`. File changes on your host are reflected immediately inside the container — no restart needed for updated plugins, though you may need to re-register the marketplace in Claude Code when adding new ones.

If `CLAUDE_MARKETPLACE_PATH` is not set in `.env`, it falls back to the empty `./marketplace/` folder (no error).

## Port Mappings

All host ports use a **41xxx offset** to avoid conflicts with common services (e.g., macOS AirPlay uses port 5000). Inside the container, apps still listen on their standard ports.

| Service | Container Port | Host Port | Access From Host |
|---|---|---|---|
| React / Express | 3000 | 41300 | `localhost:41300` |
| ASP.NET HTTP | 5000 | 41500 | `localhost:41500` |
| ASP.NET HTTPS | 5001 | 41501 | `localhost:41501` |
| Vite | 5173 | 41517 | `localhost:41517` |
| Go / Generic | 8080 | 41808 | `localhost:41808` |
| Vue / Metro | 8081 | 41881 | `localhost:41881` |
| Solana RPC | 8899 | 41889 | `localhost:41889` |
| Solana WS | 8900 | 41890 | `localhost:41890` |
| Expo | 19000 | 41900 | `localhost:41900` |
| Expo DevTools | 19001 | 41901 | `localhost:41901` |
| Android Emulator | 5554 | 41554 | `localhost:41554` |
| Android ADB | 5555 | 41555 | `localhost:41555` |

## Working with Projects

Since volumes are fully virtualized (no host bind mount), you work with code inside the container:

```bash
# Enter the container
make shell

# Clone a project
cd /workspace
git clone git@github.com:your-org/your-project.git
cd your-project

# Install dependencies
npm install              # Node.js
dotnet restore           # .NET
go mod download          # Go
cargo build              # Rust

# Start Claude Code in your project
claude
```

### Getting Files In / Out

```bash
# Copy files into the container
docker cp ./my-file.txt docker-claude:/workspace/

# Copy files out
docker cp docker-claude:/workspace/output.txt ./

# Or use git (recommended)
make shell
cd /workspace/project && git push
```

## Optional Profiles

### Solana Development

```bash
make solana-up
make shell-solana

# Inside the container
solana-test-validator
cd /workspace/my-solana-project
anchor build && anchor deploy
```

### Mobile Development (Android + Flutter + React Native)

```bash
make mobile-up
make shell-mobile

# Flutter
flutter create my_app && cd my_app && flutter build apk

# React Native
npx react-native init MyApp && cd MyApp && npx react-native run-android
```

> **Note:** iOS builds require macOS + Xcode and cannot run in Docker. Use your Mac host for iOS builds.

## Custom Builds

Build with only the stacks you need:

```bash
# Only Node.js and Go
make build-slim

# Or with full control
docker compose build \
  --build-arg INCLUDE_NODE=true \
  --build-arg INCLUDE_DOTNET=false \
  --build-arg INCLUDE_GOLANG=true \
  --build-arg INCLUDE_RUST=false \
  docker-claude
```

## VS Code Dev Container

1. Install the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension
2. Open this project folder in VS Code
3. `Ctrl+Shift+P` → "Dev Containers: Reopen in Container"
4. VS Code builds the image and connects with all extensions pre-configured (ESLint, Prettier, C# Dev Kit, Go, rust-analyzer, Flutter, Docker, GitLens, and more)

## GPU / CUDA Support

GPU support works on **Windows (WSL2)** and **Linux** only. macOS does not support NVIDIA GPUs in Docker.

### Linux

```bash
# 1. Install NVIDIA drivers
sudo apt-get install -y nvidia-driver-550

# 2. Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit

# 3. Configure and verify
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu24.04 nvidia-smi

# 4. Build with GPU
make GPU=true build
```

### Windows (WSL2)

1. Install latest NVIDIA GPU drivers for Windows
2. Docker Desktop → Settings → General → enable "Use the WSL 2 based engine"
3. Docker Desktop → Settings → Docker Engine → add:
   ```json
   { "runtimes": { "nvidia": { "path": "nvidia-container-runtime", "runtimeArgs": [] } } }
   ```
4. Build: `.\scripts\setup.ps1 -WithGpu`

## Cross-Platform: Mac ↔ Windows

| Concern | Mac | Windows |
|---|---|---|
| Setup | `make build && make up` | `.\scripts\setup.ps1` |
| Compose files | `docker-compose.yml` | `docker-compose.yml` + `docker-compose.windows.yml` |
| Docker socket | Automatic | Via WSL2 backend |
| SSH | Agent forwarding (`SSH_AUTH_SOCK`) | Keys mounted from `%USERPROFILE%\.ssh` |
| GPU | Not supported | WSL2 + NVIDIA Container Toolkit |
| Line endings | LF (automatic) | LF enforced via `.gitattributes` + setup script sanitization |

## Version Management

Switch runtime versions inside the container:

```bash
# Node.js
nvm install 22 && nvm use 22

# .NET — add a channel
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 7.0

# Rust
rustup install nightly && rustup default nightly

# Go — install a different version
curl -fsSL "https://go.dev/dl/go1.22.0.linux-$(dpkg --print-architecture).tar.gz" \
  | sudo tar -C /usr/local -xzf -
```

## Backup & Restore

The project volume (`claude-projects`) lives inside Docker's virtual filesystem — not on your host. Backups export it to a timestamped `.tar.gz` on your Mac.

### Manual Backup

```bash
# Create a backup (saved to ./backups/)
make backup
# Output: ✓ Backup complete: backups/docker-claude-backup_20260330_143000.tar.gz (2.1G)

# List all backups with sizes
make backup-list
```

### Restore

```bash
# Restore from a specific backup (stops containers, asks for confirmation)
make restore FILE=backups/docker-claude-backup_20260330_143000.tar.gz
# Then restart
make up
```

### Cleanup Old Backups

```bash
# Delete backups older than 30 days
make backup-clean
```

### Automated Daily Backups (cron)

To run backups automatically on your Mac:

```bash
# Open crontab
crontab -e

# Add this line for daily backups at 2am
0 2 * * * cd /path/to/docker-claude && make backup 2>&1 >> backups/cron.log
```

> **Note:** Backups work even when containers are stopped — they spin up a temporary container to read the volume. The `backups/` directory is git-ignored by default.

### Encrypted Backups

For sensitive projects, use AES-256-CBC encrypted backups via openssl:

```bash
# Create encrypted backup (prompts for passphrase)
make backup-enc

# Restore from encrypted backup (prompts for passphrase)
make restore-enc FILE=backups/docker-claude-backup_20260330_143000.tar.gz.enc
```

No GPG setup needed — just remember your passphrase. Losing it means the backup is unrecoverable.

### Automated Daily Encrypted Backups (cron)

```bash
crontab -e

# Uses BACKUP_PASS env var to avoid interactive prompt
0 2 * * * cd /path/to/docker-claude && BACKUP_PASS="your-passphrase" make backup-enc 2>&1 >> backups/cron.log
```

## Security

This environment is security-hardened by default. See [SECURITY.md](SECURITY.md) for full details.

### Defaults

- **Docker socket NOT mounted** — prevents host compromise
- **Ports bound to 127.0.0.1** — not visible on your local network
- **Default seccomp profile** — dangerous syscalls blocked
- **No extra capabilities** — SYS_PTRACE disabled
- **No piped script execution** — all install scripts downloaded to disk first
- **All downloads over HTTPS** — from official sources only
- **Encrypted backups available** — AES-256-CBC via openssl

### Security Overrides

When you need features that reduce security:

```bash
make DIND=true up                 # Docker-in-Docker (mounts host Docker socket)
make DEBUG=true up                # Debugger support (SYS_PTRACE + unconfined seccomp)
make DIND=true DEBUG=true up      # Both
```

### Accepted Risks

These are known and accepted for development convenience:

- **API keys in env vars** — visible in `docker inspect`; `.env` is git-ignored
- **SSH agent forwarding** — container can use (but not extract) your SSH keys
- **Git config mounted** — read-only; exposes name/email

## Troubleshooting

### Port conflict on startup (e.g., "port 5000 already in use")

All host ports use the 41xxx range to avoid conflicts. If you still hit a conflict, check what's using the port: `lsof -i :41300` (Mac) or `netstat -ano | findstr 41300` (Windows). Edit the port mapping in `docker-compose.yml` if needed.

### "Permission denied" on entrypoint.sh

The setup scripts automatically sanitize file permissions and line endings. If you skipped the setup script, run manually:

```bash
chmod +x scripts/entrypoint.sh scripts/setup.sh
sed -i '' 's/\r$//' scripts/entrypoint.sh    # Mac
sed -i 's/\r$//' scripts/entrypoint.sh       # Linux
```

### "Permission denied" on Docker socket

```bash
# Inside the container
sudo chmod 666 /var/run/docker.sock
```

### NVM not found in non-interactive shells

```bash
export NVM_DIR="/usr/local/nvm" && . "$NVM_DIR/nvm.sh"
```

### Slow file I/O on Mac

Named volumes (which we use) are the fastest option on Docker Desktop for Mac. Ensure VirtioFS is enabled: Docker Desktop → Settings → General → "VirtioFS".

### Windows line ending issues

The setup script auto-converts CRLF → LF before building. If you still see issues:

```bash
git config --global core.autocrlf input
```

## Project Structure

```
docker-claude/
├── .devcontainer/devcontainer.json   # VS Code Dev Container config
├── .dockerignore                     # Build context exclusions
├── .env.example                      # Template for environment variables
├── .gitattributes → config/          # LF line ending enforcement
├── .gitignore                        # Git exclusions
├── Dockerfile                        # Core image (conditional runtimes)
├── Dockerfile.mobile                 # Mobile profile (Android/Flutter/RN)
├── Dockerfile.solana                 # Solana profile (Solana CLI/Anchor)
├── Makefile                          # All commands (run: make help)
├── README.md                         # This file
├── SECURITY.md                       # Security documentation
├── config/
│   ├── .bashrc                       # Shell config (prompt, aliases, PATH)
│   ├── .gitattributes                # LF enforcement for cross-platform
│   ├── claude-settings.json          # Claude Code global settings (mounted into container)
│   └── claude-project-settings.example.json  # Example per-project settings
├── docker-compose.debug.yml          # Debug override (SYS_PTRACE + seccomp)
├── docker-compose.dind.yml           # DinD override (Docker socket mount)
├── docker-compose.gpu.yml            # GPU override (NVIDIA device passthrough)
├── docker-compose.windows.yml        # Windows-specific overrides
├── docker-compose.yml                # Main compose (services, volumes, ports)
├── marketplace/                      # Default (empty) plugin marketplace fallback
└── scripts/
    ├── entrypoint.sh                 # Container startup (runtime init, auth check)
    ├── setup.ps1                     # One-command setup (Windows)
    └── setup.sh                      # One-command setup (Mac/Linux)
```
