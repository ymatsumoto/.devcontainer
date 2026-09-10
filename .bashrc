# ~/.bashrc — devcontainer 用のそこそこ便利な設定

# 対話シェルでなければ何もしない
case $- in
    *i*) ;;
      *) return ;;
esac

# --- tmux 自動起動 -----------------------------------------------------------
# tmux の外にいて、かつ tmux が使えるなら main セッションにアタッチ/新規作成
if [ -z "$TMUX" ] && command -v tmux >/dev/null 2>&1; then
    exec tmux new-session -A -s main
fi

# --- 履歴 --------------------------------------------------------------------
# HISTFILE は devcontainer.json の containerEnv で .container-home/ を指している
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth        # 重複と先頭スペース付きを記録しない
shopt -s histappend           # 履歴を上書きせず追記
PROMPT_COMMAND='history -a'   # コマンドごとに履歴を書き出す（複数端末で共有）

# --- シェル挙動 --------------------------------------------------------------
shopt -s checkwinsize         # ウィンドウサイズ変更に追従
shopt -s globstar 2>/dev/null # ** で再帰グロブ
shopt -s cdspell              # cd のタイポを軽く補正

# --- 色 ----------------------------------------------------------------------
export CLICOLOR=1
if command -v dircolors >/dev/null 2>&1; then
    eval "$(dircolors -b)"
fi

# --- プロンプト（git ブランチ表示付き） --------------------------------------
__git_branch() {
    git branch --show-current 2>/dev/null | sed 's/.*/ (&)/'
}
# 緑: user@host  青: cwd  黄: git ブランチ
PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[1;33m\]$(__git_branch)\[\e[0m\]\$ '

# --- エイリアス --------------------------------------------------------------
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

# --- ページャ ----------------------------------------------------------------
export PAGER=less
export LESS='-R -F -X'        # 色を通す / 1画面なら自動終了 / 画面クリアしない

