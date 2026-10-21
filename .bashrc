# .bashrc for the devcontainer.
# ~/.bashrc is a container-local file that only sources this one (created by
# postCreateCommand), so installers appending to ~/.bashrc never touch the repo.

# Do nothing for non-interactive shells
case $- in
    *i*) ;;
      *) return ;;
esac

# --- tmux ----------------------------------------------------------------------
# Attach to (or create) the "main" session when outside tmux
if [ -z "$TMUX" ] && command -v tmux >/dev/null 2>&1; then
    exec tmux new-session -A -s main
fi

# --- Stale container check -----------------------------------------------------
# postCreateCommand stores a hash of the definition in /etc/devcontainer.stamp.
# Warn when a pull has changed the definition (or the container predates the stamp).
__dc=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
if [ "$(cd "$__dc" && cat devcontainer.json Dockerfile init.sh 2>/dev/null | sha256sum)" != "$(cat /etc/devcontainer.stamp 2>/dev/null)" ]; then
    printf '\e[1;33m[devcontainer] Definition has changed. Run "Rebuild Container".\e[0m\n'
fi
unset __dc

# --- History -------------------------------------------------------------------
# HISTFILE points into /root/.state/ via containerEnv in devcontainer.json
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth        # Skip duplicates and space-prefixed commands
shopt -s histappend           # Append instead of overwriting
PROMPT_COMMAND='history -a'   # Write after every command (shared across terminals)

# --- Shell options -------------------------------------------------------------
shopt -s checkwinsize         # Track window size changes
shopt -s globstar 2>/dev/null # Recursive ** globs
shopt -s cdspell              # Fix minor cd typos

# --- Colors --------------------------------------------------------------------
export CLICOLOR=1
if command -v dircolors >/dev/null 2>&1; then
    eval "$(dircolors -b)"
fi

# --- Prompt with git branch -----------------------------------------------------
__git_branch() {
    git branch --show-current 2>/dev/null | sed 's/.*/ (&)/'
}
# green: user@host  blue: cwd  yellow: git branch
PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[1;33m\]$(__git_branch)\[\e[0m\]\$ '

# --- Aliases -------------------------------------------------------------------
alias ls='ls --color=auto'
alias ll='ls -alhF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias g='git'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'

# --- Pager ---------------------------------------------------------------------
export PAGER=less
export LESS='-R -F -X'        # Raw colors / quit if one screen / no clear
