#!/usr/bin/env sh
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_dir=$(cd "$script_dir/.." && pwd -P)
. "$repo_dir/lib/packages.sh"
packages_repo=$(dotfile_packages_root "$repo_dir")
repo_early_init="$script_dir/early-init.el"
repo_init="$script_dir/init.el"
repo_local_emacs="$script_dir/.emacs.local"
home_emacs_dir="$HOME/.emacs.d"
home_early_init="$home_emacs_dir/early-init.el"
home_init="$home_emacs_dir/init.el"
home_local_emacs="$HOME/.emacs.local"
emacs_bin=${EMACS:-emacs}

verify_package_cache() {
  if [ -x "$packages_repo/verify.sh" ]; then
    dotfile_verify_packages "$packages_repo" >/dev/null
  else
    log "package verification tool missing: $packages_repo/verify.sh"
    return 1
  fi
}

log() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

emacs_lisp_string() {
  printf '%s\n' "$1" | sed 's/[\\"]/\\&/g'
}

install_loader_stub() {
  source=$1
  target=$2

  if [ ! -f "$source" ]; then
    log "Repo Emacs file not found: $source"
    return 1
  fi

  if [ -f "$target" ] && grep -qF "$source" "$target" 2>/dev/null; then
    log "already stubbed: $target"
    return 0
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    log "$target already exists; leaving it unchanged."
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  source_lisp=$(emacs_lisp_string "$source")
  printf '%s\n' \
    ";;; Loader stub installed by the dotfiles repo; edit the repo file instead. -*- lexical-binding: t -*-" \
    "(load \"$source_lisp\" nil 'nomessage)" \
    > "$target"
  log "installed loader stub $target -> $source"
}

warn_shadowing_init() {
  if [ -e "$HOME/.emacs" ] || [ -e "$HOME/.emacs.el" ]; then
    log "warning: ~/.emacs or ~/.emacs.el exists and may take precedence over $home_init"
  fi
}

install_emacs_config() {
  install_loader_stub "$repo_early_init" "$home_early_init"
  install_loader_stub "$repo_init" "$home_init"
  create_local_emacs_config
  warn_shadowing_init
}

create_local_emacs_config() {
  if [ -e "$home_local_emacs" ]; then
    log ".emacs.local already exists; leaving it unchanged."
    return 0
  fi

  if [ ! -f "$repo_local_emacs" ]; then
    log "Repo .emacs.local not found: $repo_local_emacs"
    return 1
  fi

  umask 077
  cp "$repo_local_emacs" "$home_local_emacs"
  log "copied $repo_local_emacs to $home_local_emacs"
}

prime_emacs_state() {
  if [ "${DOTFILE_EMACS_SKIP_PRIME:-0}" = "1" ]; then
    log "skipping Emacs package state prime by DOTFILE_EMACS_SKIP_PRIME=1"
    return 0
  fi

  if ! have "$emacs_bin"; then
    log "emacs not found; installed config will populate packages on first Emacs launch"
    return 0
  fi

  log "priming machine Emacs package state"
  DOTFILE_EMACS_PACKAGE_CACHE="$packages_repo/emacs/packages" \
    "$emacs_bin" -Q --batch -l "$repo_early_init" -l "$repo_init" \
    --eval '(message "dotfile Emacs package state primed")'
}

if [ ! -d "$packages_repo/emacs/packages" ]; then
  log "Emacs package cache not found: $packages_repo/emacs/packages"
  log "Run: sh update.sh emacs"
else
  if ! verify_package_cache; then
    log "refusing to use an unverified Emacs package cache"
    exit 1
  fi
  count=$(find "$packages_repo/emacs/packages" -maxdepth 1 -name '*.tar' -type f | wc -l | awk '{print $1}')
  log "Emacs package cache: $count tarballs at $packages_repo/emacs/packages"
fi

log "==> install Emacs config"
install_emacs_config

log "==> prime Emacs packages"
prime_emacs_state

log "Temporary GUI/TTY test: sh emacs/test-start.sh"
log "Batch smoke test: sh emacs/test-batch.sh"
