#!/usr/bin/env sh
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_dir=$(CDPATH='' cd "$script_dir/.." && pwd -P)
. "$repo_dir/lib/packages.sh"

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

# Vendored fonts live in the sibling dotfile-packages repo.
packages_root=$(dotfile_packages_root "$repo_dir")
fonts_dir="$packages_root/wezterm/fonts"

verify_packages() {
  dotfile_verify_packages "$packages_root" >/dev/null
}

if [ -z "$packages_root" ] || [ ! -d "$fonts_dir" ]; then
  log "no vendored fonts at $fonts_dir; skipping font install"
  log "install a Nerd Font manually (for example: winget install DEVCOM.JetBrainsMonoNerdFont)"
  exit 0
fi

if ! verify_packages; then
  log "vendored package verification failed: $packages_root"
  exit 1
fi

list_font_files() {
  find "$fonts_dir" -maxdepth 1 -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) -print | sort
}

# --- Windows: per-user install, no admin required ---
# Fonts are copied to %LOCALAPPDATA%\Microsoft\Windows\Fonts and registered
# under HKCU. System-wide copies in C:\Windows\Fonts are also accepted.
install_fonts_windows() {
  user_fonts_dir="$LOCALAPPDATA/Microsoft/Windows/Fonts"
  registry_key='HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

  installed=0
  skipped=0

  for font in $(list_font_files); do
    base=$(basename "$font")

    if [ -f "$user_fonts_dir/$base" ] || [ -f "/c/Windows/Fonts/$base" ]; then
      log "font already installed: $base"
      skipped=$((skipped + 1))
      continue
    fi

    mkdir -p "$user_fonts_dir"
    cp "$font" "$user_fonts_dir/"

    # Value name is informational; Windows reads the real family name from
    # the font file itself. Keep the conventional "(TrueType)" suffix.
    win_path=$(cygpath -w "$user_fonts_dir/$base" 2>/dev/null || printf '%s' "$user_fonts_dir/$base")
    MSYS2_ARG_CONV_EXCL='*' reg.exe add "$registry_key" \
      //v "$base (TrueType)" //t REG_SZ //d "$win_path" //f >/dev/null

    log "installed font: $base"
    installed=$((installed + 1))
  done

  if [ "$installed" -gt 0 ]; then
    log "note: already-running applications may need a restart to see the new fonts"
  fi
}

# --- macOS ---
install_fonts_macos() {
  for font in $(list_font_files); do
    base=$(basename "$font")
    if [ -f "$HOME/Library/Fonts/$base" ]; then
      log "font already installed: $base"
    else
      cp "$font" "$HOME/Library/Fonts/"
      log "installed font: $base"
    fi
  done
}

# --- Linux ---
install_fonts_linux() {
  target="$HOME/.local/share/fonts"
  mkdir -p "$target"

  for font in $(list_font_files); do
    base=$(basename "$font")
    if [ -f "$target/$base" ]; then
      log "font already installed: $base"
    else
      cp "$font" "$target/"
      log "installed font: $base"
    fi
  done

  if have fc-cache; then
    fc-cache -f "$target" >/dev/null 2>&1 || true
    log "refreshed font cache"
  fi
}

case "$(detect_os)" in
  windows) install_fonts_windows ;;
  macos) install_fonts_macos ;;
  linux) install_fonts_linux ;;
  *)
    log "unsupported platform for font install; install the fonts from $fonts_dir manually"
    exit 1
    ;;
esac
