#!/usr/bin/env sh
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_gitconfig="$script_dir/.gitconfig"
repo_gitignore="$script_dir/.gitignore_global"
repo_local_gitconfig="$script_dir/.gitconfig.local"
home_gitconfig="$HOME/.gitconfig"
home_gitignore="$HOME/.gitignore_global"
home_local_gitconfig="$HOME/.gitconfig.local"

log() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

# Native Windows git tools prefer C:/ style paths; MSYS2 git accepts both.
mixed_path() {
  if have cygpath; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}

git_config() {
  git config --global --includes --get "$1" 2>/dev/null || true
}

default_git_name() {
  id -un 2>/dev/null || whoami 2>/dev/null || printf 'user\n'
}

default_git_email() {
  user=$(default_git_name)

  if have hostname; then
    host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)
  else
    host=$(uname -n 2>/dev/null || true)
  fi

  host=${host%%.*}
  if [ -z "$host" ]; then
    host=localhost
  fi

  printf '%s@%s\n' "$user" "$host"
}

set_local_git_identity() {
  name=$1
  email=$2

  if ! have git; then
    log "git not found; edit $home_local_gitconfig to set user.name and user.email"
    return 0
  fi

  if [ -n "$name" ]; then
    git config --file "$home_local_gitconfig" user.name "$name"
  fi

  if [ -n "$email" ]; then
    git config --file "$home_local_gitconfig" user.email "$email"
  fi

  log "configured git identity in $home_local_gitconfig"
}

configure_git_identity() {
  if ! have git; then
    log "git not found; edit $home_local_gitconfig to set user.name and user.email"
    return 0
  fi

  current_name=$(git_config user.name)
  current_email=$(git_config user.email)

  if [ -n "$current_name" ] && [ -n "$current_email" ]; then
    log "git identity already configured: $current_name <$current_email>"
    return 0
  fi

  name=${GIT_USER_NAME:-${GIT_AUTHOR_NAME:-}}
  email=${GIT_USER_EMAIL:-${GIT_AUTHOR_EMAIL:-}}
  default_name=$(default_git_name)
  default_email=$(default_git_email)

  if [ -t 0 ] && [ -t 1 ]; then
    if [ -z "$current_name" ] && [ -z "$name" ]; then
      printf 'Git user.name [%s]: ' "$default_name"
      if ! read -r name; then
        name=
      fi
      if [ -z "$name" ]; then
        name=$default_name
      fi
    fi

    if [ -z "$current_email" ] && [ -z "$email" ]; then
      printf 'Git user.email [%s]: ' "$default_email"
      if ! read -r email; then
        email=
      fi
      if [ -z "$email" ]; then
        email=$default_email
      fi
    fi
  else
    if [ -z "$current_name" ] && [ -z "$name" ]; then
      name=$default_name
    fi

    if [ -z "$current_email" ] && [ -z "$email" ]; then
      email=$default_email
    fi
  fi

  if [ -z "$current_name" ] && [ -z "$name" ]; then
    log "git user.name is unset; set GIT_USER_NAME or run: git config --file $home_local_gitconfig user.name '$default_name'"
  fi

  if [ -z "$current_email" ] && [ -z "$email" ]; then
    log "git user.email is unset; set GIT_USER_EMAIL or run: git config --file $home_local_gitconfig user.email $default_email"
  fi

  write_name=
  write_email=

  if [ -z "$current_name" ] && [ -n "$name" ]; then
    write_name=$name
  fi

  if [ -z "$current_email" ] && [ -n "$email" ]; then
    write_email=$email
  fi

  if [ -n "$write_name" ] || [ -n "$write_email" ]; then
    set_local_git_identity "$write_name" "$write_email"
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

create_local_gitconfig() {
  if [ -e "$home_local_gitconfig" ]; then
    log ".gitconfig.local already exists; leaving it unchanged."
    return 0
  fi

  if [ ! -f "$repo_local_gitconfig" ]; then
    log "Repo .gitconfig.local not found: $repo_local_gitconfig"
    return 1
  fi

  umask 077
  cp "$repo_local_gitconfig" "$home_local_gitconfig"
  log "copied $repo_local_gitconfig to $home_local_gitconfig"
}

# The .gitconfig stub includes the repo config, then repoints excludesfile at
# the repo so .gitignore_global stays live-linked even as a stub. The include
# must come first: a later single-valued assignment wins over the included one.
link_or_copy "$repo_gitconfig" "$home_gitconfig" "# Loader stub installed by the dotfiles repo; edit the repo files instead.
[include]
	path = $(mixed_path "$repo_gitconfig")
[core]
	excludesfile = $(mixed_path "$repo_gitignore")"
link_or_copy "$repo_gitignore" "$home_gitignore" ""
create_local_gitconfig
configure_git_identity
