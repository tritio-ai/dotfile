DISABLE_AUTO_UPDATE="true"
zstyle ':omz:update' mode disabled
unset ZSH_AUTOUPDATE

# Skip oh-my-zsh's compaudit permission scan of every fpath dir; on Windows
# (MSYS2) it costs ~40 ms per shell.
ZSH_DISABLE_COMPFIX=true

_has() {
  command -v "$1" >/dev/null 2>&1
}

# Machine-local overrides. This file is created by zsh/install.sh and is not tracked here.
if [[ -r "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi

: "${MYPROXY:=localhost:7890}"

HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt AUTO_CD
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="gentoo"
plugins=(git gitfast z zsh-autosuggestions)

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
elif [[ -o interactive ]]; then
  print -u2 "oh-my-zsh not found at $ZSH; run: sh install.sh zsh"
fi

# gitstatusd: prompt git info through a daemon instead of forking git on
# every prompt redraw. The gentoo theme renders git state via vcs_info in
# gentoo_precmd, which forks git ~4 times per prompt (check-for-changes
# plus an untracked hook running a full `git status`); on Windows (MSYS2)
# each fork costs ~100 ms, so the prompt lagged ~0.5 s after every command
# inside a repo. gitstatus_query answers in a few ms. Falls back silently
# to the stock vcs_info gentoo_precmd when the daemon or its start fails.
#
# Note: gitstatus_query always reports through plain VCS_STATUS_* variables;
# the NAME argument (DOT here) only selects the daemon instance, it is not a
# variable prefix.
if [[ -r "$HOME/.gitstatus/gitstatus.plugin.zsh" ]]; then
  source "$HOME/.gitstatus/gitstatus.plugin.zsh"
  if gitstatus_start -s -1 -u -1 -c -1 -d -1 DOT >/dev/null 2>&1; then
    gentoo_precmd() {
      emulate -L zsh
      vcs_info_msg_0_=''
      # Cap the wait so a wedged daemon can never hang the prompt.
      gitstatus_query -t 2 -d "$PWD" DOT >/dev/null 2>&1 || return 0
      [[ "$VCS_STATUS_RESULT" == ok-sync ]] || return 0
      local b=$VCS_STATUS_LOCAL_BRANCH
      [[ -z "$b" ]] && b="@${VCS_STATUS_COMMIT[1,8]}"
      # Mirror the theme's actionformats when a rebase/merge/etc. is running.
      local a=''
      [[ -n "$VCS_STATUS_ACTION" ]] && a="%F{3}|%F{1}${VCS_STATUS_ACTION}"
      local s=''
      (( VCS_STATUS_HAS_STAGED )) && s+='%F{yellow}+'
      (( VCS_STATUS_HAS_UNSTAGED )) && s+='%F{red}*'
      (( VCS_STATUS_HAS_UNTRACKED )) && s+='%F{red}?'
      vcs_info_msg_0_="%F{5}(%F{2}${b}${a}${s}%F{5})%f "
    }
  fi
fi


if _has trash-put; then
  alias rm='trash-put'
fi

# tmux
alias tl="tmux list-sessions"
alias tn="tmux new -d -s"
alias ta="tmux a -t"
alias tk="tmux kill-session -t"

# vpn
unalias http https proxy 2>/dev/null
function http {
  http_proxy="$MYPROXY" "$@"
}

function https {
  https_proxy="$MYPROXY" "$@"
}

function proxy {
  http_proxy="$MYPROXY" https_proxy="$MYPROXY" HTTP_PROXY="$MYPROXY" HTTPS_PROXY="$MYPROXY" "$@"
}

# util
if _has lsd; then
  alias ls="lsd -lt"
fi

if _has btop; then
  alias top="btop"
fi

# disk usage
unalias du df duh dus 2>/dev/null
unfunction du df duh dus 2>/dev/null

function du {
  if (( $# > 1 )); then
    print -u2 'usage: du [path]'
    return 2
  fi

  local target="${1:-.}"

  if sort -hr </dev/null >/dev/null 2>&1; then
    command du -h -d 1 "$target" | sort -hr
  else
    command du -h -d 1 "$target"
  fi
}

function df {
  command df -h "$@"
}

# emacs
if _has emacs; then
  alias start-wip='emacs --daemon=wip'
  export EDITOR='emacs'
fi

if _has emacsclient; then
  alias e='emacsclient -s wip -c'
fi

# x
if [[ -d "$HOME/code/h3x" ]] && _has uv; then
  alias x='cd "$HOME/code/h3x" && uv run python main.py'
fi





# systemctl
alias sstart='sudo systemctl start '
alias sstop='sudo systemctl stop '
alias srestart='sudo systemctl restart '
alias sstatus='sudo systemctl status '

if _has docker; then
  alias dps='docker ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}"'
  alias dcps='dps -a --filter label=com.docker.compose.project=${PWD##*/}'
  alias drun='docker run -it '
  alias dexec='docker exec -it'
  alias dre='docker restart'
  alias dstat='docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"'
  alias dstats='docker stats'
  alias drmi='docker image prune -f && docker rmi -f'
  alias dls='docker image list'
  alias dpull='HTTPS_PROXY=$MYPROXY docker pull '

  if docker compose version >/dev/null 2>&1; then
    alias dup='docker compose up -d'
    alias ddown='docker compose down --remove-orphans'
    alias dlog='docker compose logs '
    alias dlogs='docker compose logs --tail 50 -f'
    alias de='${EDITOR:-emacs} compose.yml'
    alias dstop='docker compose stop'
  fi
fi

# env
if [[ "$(uname -s)" == "Darwin" ]]; then
  export ARCHFLAGS="-arch $(uname -m)"
fi
export PATH="$HOME/.local/bin:$PATH"
export LANG=en_US.UTF-8

unfunction _has

export NVM_DIR="$HOME/.nvm"

_load_nvm() {
  unfunction node npm npx nvm codex claude gemini kimi opencode pi 2>/dev/null
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  [[ -o interactive && -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
}

node() { _load_nvm; node "$@"; }
npm() { _load_nvm; npm "$@"; }
npx() { _load_nvm; npx "$@"; }
nvm() { _load_nvm; nvm "$@"; }

codex() { _load_nvm; codex "$@"; }
claude() { _load_nvm; claude "$@"; }
gemini() { _load_nvm; gemini "$@"; }
kimi() { _load_nvm; kimi "$@"; }
opencode() { _load_nvm; opencode "$@"; }
pi() { _load_nvm; pi "$@"; }
# export PATH="$HOME/app/clash/bin:$PATH"
