#!/usr/bin/env sh
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_tmux_conf="$script_dir/.tmux.conf"
home_tmux_conf="$HOME/.tmux.conf"

log() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

as_root() {
  # MSYS2/Cygwin have no privilege separation; pacman installs without sudo.
  case "$(uname -s)" in
    *MINGW*|*MSYS*|*CYGWIN*) "$@" ;;
    *)
      if [ "$(id -u)" -eq 0 ]; then
        "$@"
      else
        sudo "$@"
      fi
      ;;
  esac
}

install_tmux_if_missing() {
  if have tmux; then
    log "tmux already installed: $(command -v tmux)"
    return 0
  fi

  log "tmux not found; installing with the available package manager"

  if have apt-get; then
    as_root apt-get update
    as_root apt-get install -y tmux
  elif have dnf; then
    as_root dnf install -y tmux
  elif have yum; then
    as_root yum install -y tmux
  elif have pacman; then
    as_root pacman -Sy --needed --noconfirm tmux
  elif have zypper; then
    as_root zypper install -y tmux
  elif have brew; then
    brew install tmux
  else
    log "No supported package manager found; install tmux manually and rerun this script."
    return 1
  fi
}

link_tmux_conf() {
  if [ ! -f "$repo_tmux_conf" ]; then
    log "Repo .tmux.conf not found: $repo_tmux_conf"
    return 1
  fi

  if [ -L "$home_tmux_conf" ] && [ "$(readlink "$home_tmux_conf")" = "$repo_tmux_conf" ]; then
    log ".tmux.conf already linked: $home_tmux_conf"
    return 0
  fi

  if [ -f "$home_tmux_conf" ] && grep -qF "$repo_tmux_conf" "$home_tmux_conf" 2>/dev/null; then
    log ".tmux.conf already stubbed: $home_tmux_conf"
    return 0
  fi

  if [ -e "$home_tmux_conf" ] || [ -L "$home_tmux_conf" ]; then
    log "$home_tmux_conf already exists; leaving it unchanged."
    return 0
  fi

  # Symlinks need extra privileges on native Windows; verify the link was
  # really created (MSYS2 ln -s silently copies when privileges are missing).
  # Without symlinks, a loader stub keeps $HOME tracking the repo file.
  if MSYS=winsymlinks:nativestrict ln -s "$repo_tmux_conf" "$home_tmux_conf" 2>/dev/null && [ -L "$home_tmux_conf" ]; then
    log "linked $home_tmux_conf -> $repo_tmux_conf"
  else
    printf '%s\nsource-file "%s"\n' "# Loader stub installed by the dotfiles repo; edit the repo file instead." "$repo_tmux_conf" > "$home_tmux_conf"
    log "installed loader stub $home_tmux_conf -> $repo_tmux_conf (symlinks unavailable)"
  fi
}

reload_running_tmux() {
  if ! have tmux; then
    return 0
  fi

  if ! tmux has-session >/dev/null 2>&1; then
    return 0
  fi

  tmux source-file "$repo_tmux_conf"
  log "reloaded running tmux server from $repo_tmux_conf"
}

# A failed binary install must not block config deployment.
install_tmux_if_missing || log "continuing without the tmux binary"
link_tmux_conf
reload_running_tmux
