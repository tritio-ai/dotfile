#!/usr/bin/env sh

# Shared sibling-package repository discovery for dotfile modules.

dotfile_absolute_path() {
  base=$1
  path=$2

  case "$path" in
    /*) candidate=$path ;;
    *) candidate=$base/$path ;;
  esac

  if [ -d "$candidate" ]; then
    (CDPATH='' cd "$candidate" && pwd -P)
  else
    printf '%s\n' "$candidate"
  fi
}

dotfile_packages_root() {
  dotfile_root=$1
  dotfile_absolute_path "$dotfile_root" "${DOTFILE_PACKAGES:-../dotfile-packages}"
}

dotfile_verify_packages() {
  packages_root=$1
  [ -x "$packages_root/verify.sh" ] || return 1
  (CDPATH='' cd "$packages_root" && sh ./verify.sh)
}

dotfile_delegate_package_update() {
  dotfile_root=$1
  module=$2
  packages_root=$(dotfile_packages_root "$dotfile_root")

  if [ ! -f "$packages_root/update.sh" ]; then
    printf 'dotfile-packages updater not found: %s/update.sh\n' "$packages_root" >&2
    printf '%s\n' 'clone it beside dotfile or set DOTFILE_PACKAGES' >&2
    return 1
  fi

  printf 'delegating to %s/update.sh %s\n' "$packages_root" "$module"
  (CDPATH='' cd "$packages_root" && sh ./update.sh "$module")
}
