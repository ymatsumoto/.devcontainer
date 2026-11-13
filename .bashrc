# .bashrc for the devcontainer.
# ~/.bashrc is a container-local file that only sources this one (created by
# postCreateCommand), so installers appending to ~/.bashrc never touch the repo.

# --- Container environment -----------------------------------------------------
# A shell that sshd started (ssh into the container, herdr --remote and its panes)
# gets sshd's environment, not the container's: /root/.local/bin (claude, herdr,
# agy) is missing from PATH and HISTFILE is unset. Take what the container
# defines from PID 1. Variables already set win, except a PATH without
# /root/.local/bin, which is replaced. Before the interactive check, so that
# `ssh <container> claude ...` finds it too.
if [ -r /proc/1/environ ]; then
    while IFS= read -r -d '' __kv; do
        __k=${__kv%%=*}
        case $__k in
            HOSTNAME|HOME|TERM|SHLVL|PWD|_|*[!A-Za-z0-9_]*|[0-9]*|'') continue ;;
            PATH) case ":$PATH:" in *:/root/.local/bin:*) ;; *) export PATH="${__kv#*=}" ;; esac ;;
            *) [ -n "${!__k+x}" ] || export "$__kv" ;;
        esac
    done < /proc/1/environ
    unset __kv __k
fi

# Do nothing for non-interactive shells
case $- in
    *i*) ;;
      *) return ;;
esac

# --- tmux ----------------------------------------------------------------------
# Attach to (or create) the "main" session when outside tmux.
# Skip it inside herdr panes (herdr sets HERDR_ENV=1 in every pane): tmux
# would hide the agents from herdr. Also skip it without a terminal, e.g. the
# env probe that devcontainer exec runs.
if [ -z "$TMUX" ] && [ -z "$HERDR_ENV" ] && [ -t 0 ] && command -v tmux >/dev/null 2>&1; then
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
