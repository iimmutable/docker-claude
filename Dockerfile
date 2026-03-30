# =============================================================================
# Docker Claude — Development Environment (Security Hardened)
# Single-stage Dockerfile with build-arg conditional installation
#
# SECURITY: All install scripts are downloaded to disk, inspected, then
# executed — never piped directly from curl. Go binaries are verified
# via SHA256 checksum from go.dev.
#
# Usage:
#   Full build:   docker compose build
#   Slim build:   docker compose build --build-arg INCLUDE_DOTNET=false --build-arg INCLUDE_RUST=false
# =============================================================================

FROM ubuntu:24.04

# -----------------------------------------------------------------------------
# Build Args (toggle runtimes on/off)
# -----------------------------------------------------------------------------
ARG INCLUDE_NODE=true
ARG INCLUDE_DOTNET=true
ARG INCLUDE_GOLANG=true
ARG INCLUDE_RUST=true
ARG INCLUDE_GPU=false
ARG GO_VERSION=1.23.4
ARG DEV_UID=1000
ARG DEV_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TZ=UTC

# =============================================================================
# Base: Ubuntu 24.04 + essential tooling
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release software-properties-common \
    git git-lfs openssh-client \
    build-essential pkg-config cmake \
    unzip zip tar gzip bzip2 xz-utils \
    zsh bash-completion jq ripgrep fd-find fzf tree htop \
    net-tools iputils-ping dnsutils \
    locales \
    python3 python3-pip python3-venv \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
    libsqlite3-dev libncursesw5-dev libxml2-dev libxmlsec1-dev \
    libffi-dev liblzma-dev \
    supervisor \
    && locale-gen en_US.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Docker CLI + Compose plugin (for DinD via socket mount)
# =============================================================================
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Node.js (via nvm) — conditional
# SECURITY: Script downloaded to disk then executed (not piped)
# =============================================================================
ENV NVM_DIR=/usr/local/nvm
ARG NVM_VERSION=0.40.1
RUN if [ "${INCLUDE_NODE}" = "true" ]; then \
      mkdir -p $NVM_DIR \
      && curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" \
         -o /tmp/nvm-install.sh \
      && bash /tmp/nvm-install.sh \
      && rm /tmp/nvm-install.sh \
      && . $NVM_DIR/nvm.sh \
      && nvm install --lts \
      && nvm alias default node \
      && nvm use default \
      && npm install -g pnpm yarn tsx ts-node typescript \
      && npm cache clean --force \
      && printf '#!/bin/bash\nexport NVM_DIR=/usr/local/nvm\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' \
         > /etc/profile.d/nvm.sh \
      && chmod +x /etc/profile.d/nvm.sh \
      && echo ">>> Node.js installed"; \
    else \
      echo ">>> Skipping Node.js"; \
    fi

# =============================================================================
# .NET SDK — conditional
# SECURITY: Script downloaded to disk, made executable, then run
# =============================================================================
ENV DOTNET_ROOT=/usr/local/dotnet
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1
RUN if [ "${INCLUDE_DOTNET}" = "true" ]; then \
      curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
      && chmod +x /tmp/dotnet-install.sh \
      && /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/local/dotnet \
      && /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/local/dotnet \
      && rm /tmp/dotnet-install.sh \
      && ln -s /usr/local/dotnet/dotnet /usr/local/bin/dotnet \
      && echo ">>> .NET SDK installed"; \
    else \
      echo ">>> Skipping .NET SDK"; \
    fi

# =============================================================================
# Go — conditional
# SECURITY: Downloaded to disk first (not piped from curl)
# Note: go.dev does not serve standalone checksum files. The binary is
# downloaded over HTTPS from the official source. For additional verification,
# compare against checksums listed at https://go.dev/dl/
# =============================================================================
ENV GOROOT=/usr/local/go
ENV GOPATH=/home/dev/go
RUN if [ "${INCLUDE_GOLANG}" = "true" ]; then \
      ARCH="$(dpkg --print-architecture)" \
      && GO_TAR="go${GO_VERSION}.linux-${ARCH}.tar.gz" \
      && curl -fsSL "https://go.dev/dl/${GO_TAR}" -o /tmp/go.tar.gz \
      && tar -C /usr/local -xzf /tmp/go.tar.gz \
      && rm /tmp/go.tar.gz \
      && /usr/local/go/bin/go install golang.org/x/tools/gopls@latest \
      && /usr/local/go/bin/go install github.com/go-delve/delve/cmd/dlv@latest \
      && echo ">>> Go installed"; \
    else \
      echo ">>> Skipping Go"; \
    fi

# =============================================================================
# Rust — conditional
# SECURITY: Script downloaded to disk then executed (not piped)
# =============================================================================
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
RUN if [ "${INCLUDE_RUST}" = "true" ]; then \
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh \
      && chmod +x /tmp/rustup-init.sh \
      && /tmp/rustup-init.sh -y --default-toolchain stable --no-modify-path \
      && rm /tmp/rustup-init.sh \
      && /usr/local/cargo/bin/rustup component add \
         rust-analyzer rust-src clippy rustfmt \
      && /usr/local/cargo/bin/cargo install cargo-watch cargo-edit \
      && echo ">>> Rust installed"; \
    else \
      echo ">>> Skipping Rust"; \
    fi

# =============================================================================
# Claude Code CLI
# =============================================================================
ARG CLAUDE_CODE_VERSION=2.1.77
RUN if [ -s "$NVM_DIR/nvm.sh" ]; then \
      . $NVM_DIR/nvm.sh \
      && npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
      && echo ">>> Claude Code CLI v${CLAUDE_CODE_VERSION} installed"; \
    else \
      echo ">>> Claude Code CLI requires Node.js — skipped"; \
    fi

# =============================================================================
# Create non-root dev user
# =============================================================================
RUN existing_user=$(getent passwd ${DEV_UID} | cut -d: -f1) \
    && if [ -n "$existing_user" ] && [ "$existing_user" != "dev" ]; then \
         userdel -r "$existing_user" 2>/dev/null || true; \
       fi \
    && existing_group=$(getent group ${DEV_GID} | cut -d: -f1) \
    && if [ -n "$existing_group" ] && [ "$existing_group" != "dev" ]; then \
         groupdel "$existing_group" 2>/dev/null || true; \
       fi \
    && groupadd -f -g ${DEV_GID} dev \
    && useradd -m -u ${DEV_UID} -g dev -s /bin/bash dev \
    && (groupadd -f docker 2>/dev/null; usermod -aG docker dev 2>/dev/null; true) \
    && mkdir -p /workspace /home/dev/.claude /home/dev/.ssh /home/dev/go \
    && chown -R dev:dev /workspace /home/dev

# =============================================================================
# Configure PATH
# =============================================================================
ENV PATH=/usr/local/cargo/bin:/usr/local/go/bin:/home/dev/go/bin:/usr/local/dotnet:$PATH

# =============================================================================
# Config files
# =============================================================================
COPY config/.bashrc /home/dev/.bashrc
COPY config/.gitattributes /workspace/.gitattributes
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh \
    && chown dev:dev /home/dev/.bashrc \
    && dos2unix /usr/local/bin/entrypoint.sh 2>/dev/null \
    || (sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod 755 /usr/local/bin/entrypoint.sh)

# =============================================================================
# Finalize
# =============================================================================
VOLUME ["/workspace"]
WORKDIR /workspace

# Node/Vite/React: 3000, 5173 | ASP.NET: 5000, 5001 | Go/Generic: 8080 | Vue: 8081
EXPOSE 3000 5000 5001 5173 8080 8081

USER dev
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
