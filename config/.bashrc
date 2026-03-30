# =============================================================================
# .bashrc — Claude Code Dev Environment
# =============================================================================

# -- NVM --
export NVM_DIR="/usr/local/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# -- Go --
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH

# -- .NET --
export DOTNET_ROOT=/usr/local/dotnet
export PATH=$DOTNET_ROOT:$PATH
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

# -- Rust --
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH=$CARGO_HOME/bin:$PATH

# -- Solana (if installed) --
if [ -d "$HOME/.local/share/solana/install/active_release/bin" ]; then
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
fi

# -- Flutter (if installed) --
if [ -d "/opt/flutter/bin" ]; then
    export PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH"
fi

# -- Android (if installed) --
if [ -d "/opt/android-sdk" ]; then
    export ANDROID_HOME=/opt/android-sdk
    export ANDROID_SDK_ROOT=$ANDROID_HOME
    export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
fi

# -- SSH Agent --
if [ -S "/ssh-agent" ]; then
    export SSH_AUTH_SOCK=/ssh-agent
fi

# -- Prompt --
parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

PS1='\[\033[01;34m\]claude-dev\[\033[00m\]:\[\033[01;32m\]\w\[\033[33m\]$(parse_git_branch)\[\033[00m\]\$ '

# -- Aliases --
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias gs='git status'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline -20'
alias gd='git diff'
alias dc='docker compose'
alias ws='cd /workspace'
alias claude-login='claude login'

# -- Tab completion --
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# -- Workspace shortcut --
cd /workspace 2>/dev/null || true
