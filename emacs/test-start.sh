#!/usr/bin/env sh
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_dir=$(cd "$script_dir/.." && pwd -P)
. "$repo_dir/lib/packages.sh"
packages_repo=$(dotfile_packages_root "$repo_dir")
test_home=$(mktemp -d "${TMPDIR:-/tmp}/dotfile-emacs-home.XXXXXX")
emacs_bin=${EMACS:-emacs}

cleanup() {
  if [ "${DOTFILE_EMACS_KEEP_TEST_HOME:-0}" != "1" ]; then
    rm -rf "$test_home"
  else
    printf 'kept test home: %s\n' "$test_home"
  fi
}
trap cleanup EXIT HUP INT TERM

printf 'temporary HOME: %s\n' "$test_home"
printf 'package cache: %s\n' "$packages_repo/emacs/packages"

if [ "${DOTFILE_EMACS_SKIP_PRIME:-0}" != "1" ]; then
  prime_log="$test_home/dotfile-emacs-prime.log"
  printf 'priming package state: %s\n' "$prime_log"
  HOME="$test_home" \
  DOTFILE_EMACS_STATE_DIR="$test_home/.emacs.d/dotfile-emacs" \
  DOTFILE_EMACS_PACKAGE_CACHE="$packages_repo/emacs/packages" \
  "$emacs_bin" -Q --batch -l "$script_dir/early-init.el" -l "$script_dir/init.el" \
    --eval '(message "dotfile Emacs package state primed")' > "$prime_log" 2>&1
fi

HOME="$test_home" \
DOTFILE_EMACS_STATE_DIR="$test_home/.emacs.d/dotfile-emacs" \
DOTFILE_EMACS_PACKAGE_CACHE="$packages_repo/emacs/packages" \
DOTFILE_EMACS_NO_INSTALL=1 \
"$emacs_bin" -Q -l "$script_dir/early-init.el" -l "$script_dir/init.el" "$@"
