# Security — Docker Claude

This document covers the security measures, risks, and configuration options for the Docker Claude development environment.

## Security Model

Docker Claude runs as a **non-root user** (`dev`, UID 1000) inside an Ubuntu 24.04 container. By default, the container has:

- **No Docker socket access** (DinD disabled)
- **No extra Linux capabilities** (no SYS_PTRACE)
- **Default Docker seccomp profile** (not unconfined)
- **Ports bound to localhost only** (127.0.0.1)
- **No piped script execution** in the Dockerfile (download-then-execute)
- **SHA256 verification** for Go binary downloads

## What's Hardened

### Docker Socket (DinD)

The Docker socket (`/var/run/docker.sock`) is **not mounted by default**. Mounting it gives the container root-equivalent access to the host machine — any process inside the container could start privileged containers, access host filesystems, or modify Docker configuration.

**To enable DinD when needed:**

```bash
# Via Makefile
make DIND=true up

# Via docker compose directly
docker compose -f docker-compose.yml -f docker-compose.dind.yml up -d
```

Only enable DinD if you trust all code running in the container. Disable it when not actively needed.

### Supply Chain Security

All runtime installation scripts are **downloaded to disk first**, then executed — never piped directly from `curl`. This allows Docker layer caching to detect changes and gives you the ability to inspect scripts before execution.

| Runtime | Method |
|---|---|
| Node.js (nvm) | Download → execute → delete |
| .NET SDK | Download → chmod → execute → delete |
| Rust (rustup) | Download → chmod → execute → delete |
| Go | Download to disk → extract → delete |

Go, nvm, rustup, and dotnet-install scripts are all downloaded over HTTPS from official sources. None of these upstreams provide standalone checksum files for automated verification, so downloading to disk (instead of piping) is the practical security improvement — it enables Docker layer caching to detect unexpected changes and allows manual inspection.

### Port Binding

All exposed ports are bound to `127.0.0.1` (localhost only). This means they are **not accessible from other devices on your network**.

If you need a port accessible from other devices (e.g., testing on a phone), edit `docker-compose.yml` and remove the `127.0.0.1:` prefix for that specific port.

### Capabilities & Seccomp

The container runs with Docker's **default seccomp profile** and **no additional Linux capabilities**. This blocks dangerous syscalls like `kexec_load`, `mount`, `reboot`, and limits `ptrace` (used by debuggers).

**To enable debugging (adds SYS_PTRACE + unconfined seccomp):**

```bash
make DEBUG=true up
```

This is needed for tools like `delve` (Go debugger), `gdb`, `lldb`, `strace`, etc.

### Encrypted Backups

Backups can be encrypted with AES-256-CBC via openssl:

```bash
# Create encrypted backup (prompts for passphrase)
make backup-enc

# Restore from encrypted backup
make restore-enc FILE=backups/docker-claude-backup_20260330.tar.gz.enc
```

Unencrypted backups (`make backup`) are also available for convenience.

## Known Risks (Accepted)

These are known risks that are accepted for workflow convenience:

### API Keys in Environment Variables

The `ANTHROPIC_API_KEY` is passed via environment variable (`.env` file or `docker compose` environment). This means it's visible in `docker inspect` output and the container's `/proc/*/environ`.

**Mitigation:** The `.env` file is git-ignored. For production or shared environments, consider using Docker secrets or a vault service instead.

### SSH Agent Forwarding

On Mac/Linux, the host SSH agent socket is forwarded into the container. This means any process inside the container can use your SSH keys for the duration of the session.

**Mitigation:** The agent is forwarded read-only — the container cannot extract private key material, only use keys for authentication. On Windows, SSH keys are mounted read-only from `%USERPROFILE%\.ssh`.

### Git Config Mounted Read-Only

Your host `.gitconfig` is mounted into the container read-only. This exposes your Git identity (name, email) and configuration to the container.

**Mitigation:** Read-only mount prevents modification. If you want a separate Git identity inside the container, remove the mount from `docker-compose.yml` and configure Git manually inside the container.

## Security Overrides Cheat Sheet

| Need | Command | Risk |
|---|---|---|
| Docker-in-Docker | `make DIND=true up` | Host compromise if container is breached |
| Debugger support | `make DEBUG=true up` | Process inspection, minor privilege escalation |
| Both DinD + Debug | `make DIND=true DEBUG=true up` | Combined risks above |
| GPU passthrough | `make GPU=true build` | GPU device access |
| Network-visible ports | Edit `docker-compose.yml`, remove `127.0.0.1:` | LAN exposure |

## Reporting Security Issues

If you discover a security vulnerability in this project, please report it responsibly by opening a private issue or contacting the maintainer directly.
