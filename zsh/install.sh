#!/usr/bin/env sh
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_zshrc="$script_dir/.zshrc"
repo_local_zshrc="$script_dir/.zshrc.local"
home_zshrc="$HOME/.zshrc"
local_zshrc="$HOME/.zshrc.local"

log() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

detect_os() {
  case "$(uname -s)" in
    *MINGW*|*MSYS*|*CYGWIN*) printf 'windows\n' ;;
    Darwin) printf 'macos\n' ;;
    Linux) printf 'linux\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

login_shell() {
  if have getent; then
    shell=$(getent passwd "$(id -un)" 2>/dev/null | awk -F: '{print $7}' || true)
    if [ -n "$shell" ]; then
      printf '%s\n' "$shell"
      return 0
    fi
  fi

  if [ "$(detect_os)" = "macos" ] && have dscl; then
    shell=$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}' || true)
    if [ -n "$shell" ]; then
      printf '%s\n' "$shell"
      return 0
    fi
  fi

  printf '%s\n' "${SHELL:-}"
}

canonical_existing_path() {
  path=$1

  if [ ! -e "$path" ]; then
    return 1
  fi

  dir=$(CDPATH= cd -P "$(dirname "$path")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

same_existing_path() {
  left=$1
  right=$2

  if [ "$left" = "$right" ]; then
    return 0
  fi

  left_real=$(canonical_existing_path "$left" 2>/dev/null || true)
  right_real=$(canonical_existing_path "$right" 2>/dev/null || true)

  [ -n "$left_real" ] && [ "$left_real" = "$right_real" ]
}

shell_is_listed() {
  shell_path=$1

  [ ! -r /etc/shells ] || grep -Fxq "$shell_path" /etc/shells
}

zsh_for_chsh() {
  zsh_path=$(command -v zsh)

  if shell_is_listed "$zsh_path"; then
    printf '%s\n' "$zsh_path"
    return 0
  fi

  for candidate in /bin/zsh /usr/bin/zsh /usr/local/bin/zsh /opt/homebrew/bin/zsh; do
    if [ -x "$candidate" ] && shell_is_listed "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "$zsh_path"
}

link_or_copy() {
  source=$1
  target=$2
  stub=$3

  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    log "already linked: $target"
    return 0
  fi

  if [ -f "$target" ] && [ -n "$stub" ] && grep -qF "$source" "$target" 2>/dev/null; then
    log "already stubbed: $target"
    return 0
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    log "$target already exists; leaving it unchanged."
    return 0
  fi

  # Symlinks need extra privileges on native Windows; verify the link was
  # really created (MSYS2 ln -s silently copies when privileges are missing).
  # Without symlinks, a loader stub keeps $HOME tracking the repo file.
  if MSYS=winsymlinks:nativestrict ln -s "$source" "$target" 2>/dev/null && [ -L "$target" ]; then
    log "linked $target -> $source"
  elif [ -n "$stub" ]; then
    printf '%s\n' "$stub" > "$target"
    log "installed loader stub $target -> $source (symlinks unavailable)"
  else
    cp "$source" "$target"
    log "copied $source to $target (symlinks unavailable; recopy after editing the repo file)"
  fi
}

link_shared_zshrc() {
  if [ ! -f "$repo_zshrc" ]; then
    log "Repo .zshrc not found: $repo_zshrc"
    return 1
  fi

  link_or_copy "$repo_zshrc" "$home_zshrc" "# Loader stub installed by the dotfiles repo; edit the repo file instead.
source \"$repo_zshrc\""
}

create_local_zshrc() {
  if [ -e "$local_zshrc" ]; then
    log ".zshrc.local already exists; leaving it unchanged."
    return 0
  fi

  if [ ! -f "$repo_local_zshrc" ]; then
    log "Repo .zshrc.local not found: $repo_local_zshrc"
    return 1
  fi

  umask 077
  cp "$repo_local_zshrc" "$local_zshrc"
  log "copied $repo_local_zshrc to $local_zshrc"
}

change_default_shell() {
  zsh_path=$1

  if [ -r /etc/shells ] && ! shell_is_listed "$zsh_path"; then
    log "default shell unchanged; $zsh_path is not listed in /etc/shells"
    return 1
  fi

  if have chsh; then
    chsh -s "$zsh_path"
    log "default shell changed to $zsh_path"
  else
    log "chsh not found; change the default shell manually to $zsh_path"
  fi
}

set_default_shell() {
  if [ "$(detect_os)" = "windows" ]; then
    log "chsh does not apply on Windows; select zsh via the terminal instead (see the wezterm module)"
    return 0
  fi

  zsh_path=$(zsh_for_chsh)
  current_shell=$(login_shell)

  if [ -n "$current_shell" ] && same_existing_path "$current_shell" "$zsh_path"; then
    log "default shell already zsh: $zsh_path"
    return 0
  fi

  case "${SET_DEFAULT_ZSH-}" in
    1)
      change_default_shell "$zsh_path"
      return $?
      ;;
    0)
      log "default shell unchanged by SET_DEFAULT_ZSH=0; run: chsh -s $zsh_path"
      return 0
      ;;
    "") ;;
    *)
      log "SET_DEFAULT_ZSH must be 1 or 0"
      return 1
      ;;
  esac

  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Set default shell from %s to %s? [y/N] ' "${current_shell:-unknown}" "$zsh_path"
    if read -r answer; then
      case "$answer" in
        y|Y|yes|YES|Yes) change_default_shell "$zsh_path" ;;
        *) log "default shell unchanged; run: chsh -s $zsh_path" ;;
      esac
    else
      log "default shell unchanged; run: chsh -s $zsh_path"
    fi
  else
    log "default shell is ${current_shell:-unknown}; run SET_DEFAULT_ZSH=1 sh install.sh zsh to change it to $zsh_path"
  fi
}

log "==> install zsh binary"
sh "$script_dir/install-zsh.sh"

log "==> link zsh config"
link_shared_zshrc
create_local_zshrc

log "==> install oh my zsh"
sh "$script_dir/install-oh-my-zsh.sh"

set_default_shell
