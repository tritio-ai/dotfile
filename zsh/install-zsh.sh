#!/usr/bin/env sh
set -eu

log() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

detect_os() {
  case "$(uname -s)" in
    *MINGW*|*MSYS*|*CYGWIN*) printf 'windows\n' ;;
    Darwin) printf 'macos\n' ;;
    Linux) printf 'linux\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

# On Windows there is no native zsh; it lives in the MSYS2 environment.
# Git Bash and MSYS2 shells both report MINGW/MSYS via uname, so detect the
# zsh binary in the usual MSYS2 root even when it is not on PATH.
find_windows_zsh() {
  if have zsh; then
    command -v zsh
    return 0
  fi

  for candidate in \
    /c/msys64/usr/bin/zsh.exe \
    "$HOME/code/msys64/usr/bin/zsh.exe" \
    /msys64/usr/bin/zsh.exe; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

find_windows_pacman() {
  if have pacman; then
    command -v pacman
    return 0
  fi

  for candidate in \
    /c/msys64/usr/bin/pacman.exe \
    "$HOME/code/msys64/usr/bin/pacman.exe" \
    /msys64/usr/bin/pacman.exe; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

install_zsh_windows() {
  if zsh_path=$(find_windows_zsh); then
    log "zsh already installed: $zsh_path"
    log "note: on Windows the shell is selected by the terminal (WezTerm default_prog), not chsh"
    return 0
  fi

  if ! pacman_path=$(find_windows_pacman); then
    log "MSYS2 pacman not found. Install MSYS2 first (winget install MSYS2.MSYS2) and rerun."
    return 1
  fi

  log "installing zsh via MSYS2 pacman: $pacman_path"
  "$pacman_path" -Sy --needed --noconfirm zsh

  if zsh_path=$(find_windows_zsh); then
    log "zsh installed: $zsh_path"
  else
    log "pacman finished but zsh was not found under /c/msys64"
    return 1
  fi
}

install_zsh_unix() {
  if have zsh; then
    log "zsh already installed: $(command -v zsh)"
    return 0
  fi

  log "zsh not found; installing with the available package manager"

  if have apt-get; then
    as_root apt-get update
    as_root apt-get install -y zsh
  elif have dnf; then
    as_root dnf install -y zsh
  elif have yum; then
    as_root yum install -y zsh
  elif have pacman; then
    as_root pacman -Sy --needed --noconfirm zsh
  elif have zypper; then
    as_root zypper install -y zsh
  elif have brew; then
    brew install zsh
  else
    log "No supported package manager found; install zsh manually and rerun this script."
    return 1
  fi
}

os=$(detect_os)
log "detected platform: $os"

case "$os" in
  windows) install_zsh_windows ;;
  *) install_zsh_unix ;;
esac
