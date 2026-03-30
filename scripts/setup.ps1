# =============================================================================
# setup.ps1 — One-command setup for Claude Code Dev Environment (Windows)
#
# Usage (run in PowerShell):
#   .\scripts\setup.ps1                    # Full build, all stacks
#   .\scripts\setup.ps1 -Slim              # Node + Go only
#   .\scripts\setup.ps1 -WithSolana        # Include Solana profile
#   .\scripts\setup.ps1 -WithMobile        # Include Mobile profile
#   .\scripts\setup.ps1 -WithGpu           # Include NVIDIA GPU support
#   .\scripts\setup.ps1 -All               # Everything
# =============================================================================

[CmdletBinding()]
param(
    [switch]$Slim,
    [switch]$WithSolana,
    [switch]$WithMobile,
    [switch]$WithGpu,
    [switch]$All
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectDir

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Claude Code Dev Environment — Setup (Windows)       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# -- Config --
$IncludeNode   = "true"
$IncludeDotnet = if ($Slim) { "false" } else { "true" }
$IncludeGolang = "true"
$IncludeRust   = if ($Slim) { "false" } else { "true" }
$IncludeGpu    = if ($WithGpu) { "true" } else { "false" }

if ($All) {
    $WithSolana = $true
    $WithMobile = $true
    Write-Host "Building everything" -ForegroundColor Cyan
}

# ===== [1/6] Preflight =====
Write-Host "`n[1/6] Preflight checks..." -ForegroundColor Cyan

try {
    $dockerVersion = docker --version
    Write-Host "✓ $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker not found. Install Docker Desktop for Windows." -ForegroundColor Red
    Write-Host "  → https://docs.docker.com/desktop/install/windows-install/" -ForegroundColor Yellow
    exit 1
}

try {
    docker info 2>$null | Out-Null
    Write-Host "✓ Docker daemon running" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker daemon not running. Start Docker Desktop." -ForegroundColor Red
    exit 1
}

# Check WSL2 backend
$wslStatus = wsl --status 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ WSL2 available" -ForegroundColor Green
} else {
    Write-Host "! WSL2 not detected — Docker Desktop requires WSL2 backend" -ForegroundColor Yellow
}

# GPU check
if ($WithGpu) {
    try {
        nvidia-smi | Out-Null
        Write-Host "✓ NVIDIA GPU detected" -ForegroundColor Green
    } catch {
        Write-Host "! NVIDIA GPU not detected — GPU builds may fail" -ForegroundColor Yellow
    }
}

# ===== [2/6] Environment =====
Write-Host "`n[2/6] Configuring environment..." -ForegroundColor Cyan

if (-not (Test-Path ".env")) {
    @"
# Claude Code API Key (leave empty for OAuth login)
ANTHROPIC_API_KEY=

# Windows user profile (for .gitconfig and .ssh mounts)
USERPROFILE=$env:USERPROFILE
"@ | Out-File -FilePath ".env" -Encoding UTF8

    Write-Host "✓ Created .env file" -ForegroundColor Green
    Write-Host "  → Edit .env to add your ANTHROPIC_API_KEY" -ForegroundColor Yellow
} else {
    Write-Host "✓ .env file already exists" -ForegroundColor Green
}

# ===== [3/6] Build core =====
Write-Host "`n[3/6] Building core image..." -ForegroundColor Cyan
Write-Host "  Stacks: Node=$IncludeNode .NET=$IncludeDotnet Go=$IncludeGolang Rust=$IncludeRust GPU=$IncludeGpu"

docker compose `
    -f docker-compose.yml `
    -f docker-compose.windows.yml `
    build `
    --build-arg INCLUDE_NODE=$IncludeNode `
    --build-arg INCLUDE_DOTNET=$IncludeDotnet `
    --build-arg INCLUDE_GOLANG=$IncludeGolang `
    --build-arg INCLUDE_RUST=$IncludeRust `
    --build-arg INCLUDE_GPU=$IncludeGpu `
    claude-dev

if ($LASTEXITCODE -ne 0) { Write-Host "✗ Core build failed" -ForegroundColor Red; exit 1 }
Write-Host "✓ Core image built" -ForegroundColor Green

# ===== [4/6] Profile images =====
Write-Host "`n[4/6] Building profile images..." -ForegroundColor Cyan

if ($WithSolana) {
    docker compose -f docker-compose.yml -f docker-compose.windows.yml --profile solana build claude-solana
    if ($LASTEXITCODE -ne 0) { Write-Host "✗ Solana build failed" -ForegroundColor Red; exit 1 }
    Write-Host "✓ Solana image built" -ForegroundColor Green
} else {
    Write-Host "– Solana skipped (use -WithSolana to include)" -ForegroundColor Yellow
}

if ($WithMobile) {
    docker compose -f docker-compose.yml -f docker-compose.windows.yml --profile mobile build claude-mobile
    if ($LASTEXITCODE -ne 0) { Write-Host "✗ Mobile build failed" -ForegroundColor Red; exit 1 }
    Write-Host "✓ Mobile image built" -ForegroundColor Green
} else {
    Write-Host "– Mobile skipped (use -WithMobile to include)" -ForegroundColor Yellow
}

# ===== [5/6] Volumes =====
Write-Host "`n[5/6] Creating volumes..." -ForegroundColor Cyan
docker volume create claude-projects 2>$null
docker volume create claude-auth 2>$null
Write-Host "✓ Volumes ready" -ForegroundColor Green

# ===== [6/6] Start =====
Write-Host "`n[6/6] Starting services..." -ForegroundColor Cyan

$profiles = @()
if ($WithSolana) { $profiles += "--profile"; $profiles += "solana" }
if ($WithMobile) { $profiles += "--profile"; $profiles += "mobile" }

$composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.windows.yml") + $profiles + @("up", "-d")
& docker compose @composeArgs

if ($LASTEXITCODE -ne 0) { Write-Host "✗ Failed to start services" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✓ Setup complete!                                      ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Quick start:" -ForegroundColor White
Write-Host "  docker compose -f docker-compose.yml -f docker-compose.windows.yml exec claude-dev bash" -ForegroundColor Cyan
Write-Host "  docker compose -f docker-compose.yml -f docker-compose.windows.yml exec claude-dev claude" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tip: Create a shortcut alias in your PowerShell profile:" -ForegroundColor Yellow
Write-Host '  function cdev { docker compose -f docker-compose.yml -f docker-compose.windows.yml exec claude-dev $args }' -ForegroundColor DarkGray
Write-Host ""
