# =============================================================================
# Makefile — Docker Claude Dev Environment
# Run 'make help' to see all available commands
# =============================================================================

.PHONY: help build build-slim build-all up down restart shell claude login \
        solana-up mobile-up status logs clean nuke health \
        backup restore backup-list backup-clean

# Detect OS for compose file selection
ifeq ($(OS),Windows_NT)
    COMPOSE_FILES := -f docker-compose.yml -f docker-compose.windows.yml
else
    COMPOSE_FILES := -f docker-compose.yml
endif

# GPU override (use: make build GPU=true)
GPU ?= false
ifeq ($(GPU),true)
    COMPOSE_FILES += -f docker-compose.gpu.yml
endif

COMPOSE := docker compose $(COMPOSE_FILES)

# =============================================================================
# Help
# =============================================================================

help: ## Show this help
	@echo ""
	@echo "Docker Claude Dev Environment"
	@echo "============================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make build              Build core image (all stacks)"
	@echo "  make build-slim         Build with Node + Go only"
	@echo "  make up                 Start core environment"
	@echo "  make solana-up          Start with Solana profile"
	@echo "  make claude             Launch Claude Code CLI"
	@echo "  make GPU=true build     Build with NVIDIA GPU support"
	@echo ""

# =============================================================================
# Build
# =============================================================================

build: ## Build core image (all stacks)
	$(COMPOSE) build \
		--build-arg INCLUDE_NODE=true \
		--build-arg INCLUDE_DOTNET=true \
		--build-arg INCLUDE_GOLANG=true \
		--build-arg INCLUDE_RUST=true \
		--build-arg INCLUDE_GPU=$(GPU) \
		docker-claude

build-slim: ## Build slim image (Node + Go only)
	$(COMPOSE) build \
		--build-arg INCLUDE_NODE=true \
		--build-arg INCLUDE_DOTNET=false \
		--build-arg INCLUDE_GOLANG=true \
		--build-arg INCLUDE_RUST=false \
		--build-arg INCLUDE_GPU=false \
		docker-claude

build-all: build ## Build all images including profiles
	$(COMPOSE) --profile solana build docker-claude-solana
	$(COMPOSE) --profile mobile build docker-claude-mobile

build-no-cache: ## Build core image without cache
	$(COMPOSE) build --no-cache docker-claude

# =============================================================================
# Run
# =============================================================================

up: ## Start core environment
	$(COMPOSE) up -d

down: ## Stop all services (volumes persist)
	$(COMPOSE) --profile solana --profile mobile down

restart: down up ## Restart all services

solana-up: ## Start with Solana profile
	$(COMPOSE) --profile solana up -d

mobile-up: ## Start with Mobile profile
	$(COMPOSE) --profile mobile up -d

all-up: ## Start everything
	$(COMPOSE) --profile solana --profile mobile up -d

# =============================================================================
# Interactive
# =============================================================================

shell: ## Open bash shell in docker-claude
	$(COMPOSE) exec docker-claude bash

claude: ## Launch Claude Code CLI
	$(COMPOSE) exec docker-claude bash -c '. /usr/local/nvm/nvm.sh && claude'

login: ## Run Claude OAuth login
	$(COMPOSE) exec docker-claude bash -c '. /usr/local/nvm/nvm.sh && claude login'

shell-solana: ## Open shell in Solana container
	$(COMPOSE) --profile solana exec docker-claude-solana bash

shell-mobile: ## Open shell in Mobile container
	$(COMPOSE) --profile mobile exec docker-claude-mobile bash

# =============================================================================
# Status & Logs
# =============================================================================

status: ## Show running containers and volumes
	@echo "=== Containers ==="
	@docker ps --filter "name=docker-claude" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "=== Volumes ==="
	@docker volume ls --filter "name=claude-"
	@echo ""
	@echo "=== Image Sizes ==="
	@docker images --filter "reference=docker-claude*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

logs: ## Follow logs for docker-claude
	$(COMPOSE) logs -f docker-claude

logs-all: ## Follow logs for all services
	$(COMPOSE) --profile solana --profile mobile logs -f

# =============================================================================
# Health & Diagnostics
# =============================================================================

health: ## Run health check on all installed runtimes
	$(COMPOSE) exec docker-claude bash /workspace/.health-check.sh 2>/dev/null || \
	$(COMPOSE) exec docker-claude bash -c '\
		echo "=== Runtime Health Check ===" && \
		echo "" && \
		. /usr/local/nvm/nvm.sh 2>/dev/null && \
		echo -n "Node.js:  " && (node --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "npm:      " && (npm --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "pnpm:     " && (pnpm --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "yarn:     " && (yarn --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "tsc:      " && (tsc --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n ".NET:     " && (dotnet --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "Go:       " && (go version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "Rust:     " && (rustc --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "Cargo:    " && (cargo --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "Docker:   " && (docker --version 2>/dev/null || echo "NOT AVAILABLE") && \
		echo -n "Git:      " && (git --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "Claude:   " && (claude --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "Solana:   " && (solana --version 2>/dev/null || echo "NOT INSTALLED") && \
		echo -n "Flutter:  " && (flutter --version 2>/dev/null | head -1 || echo "NOT INSTALLED") && \
		echo "" && \
		echo "=== Auth Status ===" && \
		if [ -n "$$ANTHROPIC_API_KEY" ]; then echo "API Key: configured"; \
		elif [ -f ~/.claude/credentials.json ] || [ -f ~/.claude/.credentials.json ]; then echo "OAuth: session found"; \
		else echo "Auth: NOT CONFIGURED — run claude login"; fi && \
		echo "" && \
		echo "=== Docker Socket ===" && \
		if [ -S /var/run/docker.sock ]; then echo "Socket: available"; else echo "Socket: NOT MOUNTED"; fi && \
		echo "" && \
		echo "=== Workspace ===" && \
		echo "Projects: $$(find /workspace -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)" && \
		echo "Disk usage: $$(du -sh /workspace 2>/dev/null | cut -f1)" \
	'

# =============================================================================
# Cleanup
# =============================================================================

clean: ## Stop containers and remove images (volumes persist)
	$(COMPOSE) --profile solana --profile mobile down --rmi local

nuke: ## ⚠️  Remove EVERYTHING (containers, volumes, images)
	@echo "⚠️  This will delete ALL containers, volumes, and images."
	@echo "   Your project code in the volume will be PERMANENTLY LOST."
	@read -p "   Type 'yes' to confirm: " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		$(COMPOSE) --profile solana --profile mobile down -v --rmi local; \
		echo "Done. Everything removed."; \
	else \
		echo "Cancelled."; \
	fi

# =============================================================================
# Backup & Restore
# =============================================================================

BACKUP_DIR ?= ./backups

backup: ## Backup project volume to a timestamped tar.gz
	@mkdir -p $(BACKUP_DIR)
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S) && \
	BACKUP_FILE="$(BACKUP_DIR)/docker-claude-backup_$${TIMESTAMP}.tar.gz" && \
	echo "Backing up /workspace → $${BACKUP_FILE} ..." && \
	docker run --rm \
		-v claude-projects:/workspace:ro \
		-v $$(cd $(BACKUP_DIR) && pwd):/backup \
		ubuntu:24.04 \
		tar czf /backup/docker-claude-backup_$${TIMESTAMP}.tar.gz -C /workspace . && \
	SIZE=$$(du -h "$${BACKUP_FILE}" | cut -f1) && \
	echo "✓ Backup complete: $${BACKUP_FILE} ($${SIZE})"

restore: ## Restore project volume from a backup (usage: make restore FILE=backups/docker-claude-backup_xxx.tar.gz)
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make restore FILE=backups/docker-claude-backup_YYYYMMDD_HHMMSS.tar.gz"; \
		echo ""; \
		echo "Available backups:"; \
		ls -lh $(BACKUP_DIR)/docker-claude-backup_*.tar.gz 2>/dev/null || echo "  No backups found in $(BACKUP_DIR)/"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "✗ File not found: $(FILE)"; \
		exit 1; \
	fi
	@echo "⚠️  This will REPLACE all contents of the project volume with the backup."
	@echo "   Backup file: $(FILE)"
	@read -p "   Type 'yes' to confirm: " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		echo "Stopping containers..." && \
		$(COMPOSE) --profile solana --profile mobile down && \
		echo "Restoring from $(FILE) ..." && \
		docker run --rm \
			-v claude-projects:/workspace \
			-v $$(cd $$(dirname $(FILE)) && pwd):/backup:ro \
			ubuntu:24.04 \
			sh -c "rm -rf /workspace/* /workspace/.[!.]* 2>/dev/null; tar xzf /backup/$$(basename $(FILE)) -C /workspace" && \
		echo "✓ Restore complete. Run 'make up' to start." ; \
	else \
		echo "Cancelled."; \
	fi

backup-list: ## List all available backups
	@echo "=== Backups in $(BACKUP_DIR)/ ==="
	@ls -lh $(BACKUP_DIR)/docker-claude-backup_*.tar.gz 2>/dev/null \
		| awk '{printf "  %s  %s  %s\n", $$9, $$5, $$6" "$$7" "$$8}' \
		|| echo "  No backups found."
	@echo ""
	@echo "Total: $$(ls $(BACKUP_DIR)/docker-claude-backup_*.tar.gz 2>/dev/null | wc -l | tr -d ' ') backup(s)"
	@du -sh $(BACKUP_DIR) 2>/dev/null | awk '{printf "  Disk usage: %s\n", $$1}' || true

backup-clean: ## Delete backups older than 30 days
	@echo "Removing backups older than 30 days from $(BACKUP_DIR)/ ..."
	@find $(BACKUP_DIR) -name "docker-claude-backup_*.tar.gz" -mtime +30 -print -delete 2>/dev/null \
		|| echo "  No old backups found."
	@echo "Done."

