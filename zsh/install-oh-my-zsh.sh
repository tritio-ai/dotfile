#!/usr/bin/env sh
set -eu

log() {
  printf '%s\n' "$*"
}

script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
repo_dir=$(CDPATH='' cd "$script_dir/.." && pwd -P)
. "$repo_dir/lib/packages.sh"

have() {
  command -v "$1" >/dev/null 2>&1
}

# Vendored packages live in a sibling repo so the dotfile repo stays small.
# Override with DOTFILE_PACKAGES if the repo lives elsewhere.
packages_root=$(dotfile_packages_root "$repo_dir")
packages_zsh_dir="$packages_root/zsh"

omz_dir="$HOME/.oh-my-zsh"
autosuggestions_dir="$omz_dir/custom/plugins/zsh-autosuggestions"
gitstatus_dir="$HOME/.gitstatus"
omz_remote="https://github.com/ohmyzsh/ohmyzsh.git"
autosuggestions_remote="https://github.com/zsh-users/zsh-autosuggestions.git"
gitstatus_remote="https://github.com/romkatv/gitstatus.git"
omz_commit="bf77e350e04bd202921a50529e4f54deba3db7e2"
autosuggestions_commit="85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5"
gitstatus_commit="7822a026b77fb810e74055836d62cbe5b133eade"

verify_packages() {
  dotfile_verify_packages "$packages_root" >/dev/null
}

allow_network() {
  if [ "${DOTFILE_ALLOW_NETWORK:-0}" = "1" ]; then
    return 0
  fi
  log "network fallback disabled; set DOTFILE_ALLOW_NETWORK=1 to enable it"
  return 1
}

first_existing_file() {
  for path in "$@"; do
    if [ -f "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

extract_archive() {
  archive=$1
  destination=$2
  marker=$3
  name=$4

  if [ -e "$marker" ]; then
    log "$name already installed: $destination"
    return 0
  fi

  if [ -e "$destination" ]; then
    log "$destination exists but $marker is missing; leaving it unchanged."
    return 1
  fi

  tmpdir=$(mktemp -d)
  extract_status=0

  case "$archive" in
    *.zip)
      if ! have unzip; then
        log "unzip is required to extract $archive"
        return 1
      fi
      unzip -q "$archive" -d "$tmpdir" || extract_status=$?
      ;;
    *.tar.gz|*.tgz)
      # winsymlinks lets tar create real symlinks when Windows grants the
      # privilege (Developer Mode); without it, symlinked entries are skipped.
      MSYS=winsymlinks CYGWIN=winsymlinks tar -xzf "$archive" -C "$tmpdir" || extract_status=$?
      ;;
    *)
      log "Unsupported archive format: $archive"
      return 1
      ;;
  esac

  # Symlink entries can fail on Windows without symlink privileges. That is
  # only fatal when the marker file itself did not make it out.
  if [ "$extract_status" -ne 0 ]; then
    log "note: extractor reported errors (often Windows symlink permissions); checking required files"
  fi

  source_dir=$(find "$tmpdir" -type f -name "$(basename "$marker")" -exec dirname {} \; | head -n 1)
  if [ -z "$source_dir" ]; then
    log "$archive does not contain $(basename "$marker")."
    return 1
  fi

  mkdir -p "$(dirname "$destination")"
  cp -a "$source_dir" "$destination"
  rm -rf "$tmpdir"
  log "installed $name from $archive"
}

# --- Oh My Zsh ---

omz_offline_archive() {
  [ -n "$packages_root" ] || return 1
  first_existing_file \
    "$packages_zsh_dir/oh-my-zsh.tar.gz" \
    "$packages_zsh_dir/oh-my-zsh.tgz" \
    "$packages_zsh_dir/oh-my-zsh.zip" \
    "$packages_zsh_dir/ohmyzsh.tar.gz" \
    "$packages_zsh_dir/ohmyzsh.tgz" \
    "$packages_zsh_dir/ohmyzsh.zip"
}

install_omz_offline() {
  archive=$(omz_offline_archive) || return 1
  extract_archive "$archive" "$omz_dir" "$omz_dir/oh-my-zsh.sh" "Oh My Zsh"
}

install_omz_online() {
  if [ -e "$omz_dir/oh-my-zsh.sh" ]; then
    log "Oh My Zsh already installed: $omz_dir"
    return 0
  fi

  if ! have git; then
    log "git is required for the online Oh My Zsh install."
    return 1
  fi

  allow_network || return 1
  log "no vendored Oh My Zsh archive; cloning pinned commit $omz_commit"
  git clone --depth 1 "https://github.com/ohmyzsh/ohmyzsh.git" "$omz_dir"
  (cd "$omz_dir" && git fetch --depth 1 origin "$omz_commit" && git checkout --detach "$omz_commit")
}

# --- zsh-autosuggestions ---

autosuggestions_offline_archive() {
  [ -n "$packages_root" ] || return 1
  first_existing_file \
    "$packages_zsh_dir/zsh-autosuggestions.tar.gz" \
    "$packages_zsh_dir/zsh-autosuggestions.tgz" \
    "$packages_zsh_dir/zsh-autosuggestions.zip"
}

install_autosuggestions_offline() {
  archive=$(autosuggestions_offline_archive) || return 1
  extract_archive "$archive" "$autosuggestions_dir" "$autosuggestions_dir/zsh-autosuggestions.zsh" "zsh-autosuggestions"
}

install_autosuggestions_online() {
  if [ -e "$autosuggestions_dir/zsh-autosuggestions.zsh" ]; then
    log "zsh-autosuggestions already installed: $autosuggestions_dir"
    return 0
  fi

  if ! have git; then
    log "git is required for the online zsh-autosuggestions install."
    return 1
  fi

  allow_network || return 1
  log "no vendored zsh-autosuggestions archive; cloning from $autosuggestions_remote"
  mkdir -p "$(dirname "$autosuggestions_dir")"
  git clone --depth 1 "$autosuggestions_remote" "$autosuggestions_dir"
  (cd "$autosuggestions_dir" && git fetch --depth 1 origin "$autosuggestions_commit" && git checkout --detach "$autosuggestions_commit")
}

# --- gitstatus ---

# The .zshrc routes the gentoo theme's git segment through gitstatusd; the
# daemon answers in a few ms instead of forking git ~4 times per prompt.
# Each fork costs ~100 ms on Windows, so the daemon is only worth it there;
# on Linux/macOS forks are cheap and the stock vcs_info path is fast enough.
# Without ~/.gitstatus the .zshrc silently falls back to vcs_info.
gitstatus_offline_archive() {
  [ -n "$packages_root" ] || return 1
  first_existing_file \
    "$packages_zsh_dir/gitstatus.tar.gz" \
    "$packages_zsh_dir/gitstatus.tgz" \
    "$packages_zsh_dir/gitstatus.zip"
}

install_gitstatus_offline() {
  archive=$(gitstatus_offline_archive) || return 1
  extract_archive "$archive" "$gitstatus_dir" "$gitstatus_dir/gitstatus.plugin.zsh" "gitstatus"
}

install_gitstatus_online() {
  if [ -e "$gitstatus_dir/gitstatus.plugin.zsh" ]; then
    log "gitstatus already installed: $gitstatus_dir"
    return 0
  fi

  if ! have git; then
    log "git is required for the online gitstatus install."
    return 1
  fi

  allow_network || return 1
  log "no vendored gitstatus archive; cloning from $gitstatus_remote"
  git clone --depth 1 "$gitstatus_remote" "$gitstatus_dir"
  (cd "$gitstatus_dir" && git fetch --depth 1 origin "$gitstatus_commit" && git checkout --detach "$gitstatus_commit")
}

# --- dispatch: offline packages first, online fallback ---

if [ -n "$packages_root" ] && [ -d "$packages_zsh_dir" ]; then
  log "using vendored packages: $packages_zsh_dir"
  verify_packages || {
    log "vendored package verification failed: $packages_root"
    exit 1
  }
else
  log "no vendored package directory at $packages_zsh_dir; falling back to online install"
fi

if ! install_omz_offline; then
  install_omz_online
fi

if ! install_autosuggestions_offline; then
  install_autosuggestions_online
fi

# gitstatus only pays off on Windows (see the gitstatus section above).
case "$(uname -s)" in
  *MINGW*|*MSYS*|*CYGWIN*)
    if ! install_gitstatus_offline; then
      install_gitstatus_online
    fi
    ;;
  *)
    log "skipping gitstatus (only needed on Windows; .zshrc falls back to vcs_info)"
    ;;
esac
