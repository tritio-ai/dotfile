#!/usr/bin/env sh
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_wezterm_lua="$script_dir/.wezterm.lua"
repo_local_lua="$script_dir/.wezterm.lua.local"
home_wezterm_lua="$HOME/.wezterm.lua"
home_local_lua="$HOME/.wezterm.lua.local"

log() {
  printf '%s\n' "$*"
}

# WezTerm is a native Windows app; its Lua accepts C:/ style paths.
mixed_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}

link_or_copy() {
  source=$1
  target=$2
  stub=$3

  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    log "already linked: $target"
    return 0
  fi

  if [ -f "$target" ] && [ -n "$stub" ] && grep -qF "$(mixed_path "$source")" "$target" 2>/dev/null; then
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

create_local_lua() {
  if [ -e "$home_local_lua" ]; then
    log ".wezterm.lua.local already exists; leaving it unchanged."
    return 0
  fi

  if [ ! -f "$repo_local_lua" ]; then
    log "Repo .wezterm.lua.local not found: $repo_local_lua"
    return 1
  fi

  umask 077
  cp "$repo_local_lua" "$home_local_lua"
  log "copied $repo_local_lua to $home_local_lua"
}

link_or_copy "$repo_wezterm_lua" "$home_wezterm_lua" "-- Loader stub installed by the dotfiles repo; edit the repo file instead.
return dofile('$(mixed_path "$repo_wezterm_lua")')"
create_local_lua

log "==> install fonts"
sh "$script_dir/install-fonts.sh"
