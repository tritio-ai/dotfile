#!/usr/bin/env sh
set -eu

# The vendored archives live in the sibling dotfile-packages repo, which
# maintains its own updater and VERSIONS.org. This module updater delegates
# to it so the root `sh update.sh zsh` protocol keeps working.
#
# Override with DOTFILE_PACKAGES if the packages repo lives elsewhere.
# Network proxy: export MYPROXY=host:port before running.

script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
repo_dir=$(CDPATH='' cd "$script_dir/.." && pwd -P)
. "$repo_dir/lib/packages.sh"
dotfile_delegate_package_update "$repo_dir" zsh
