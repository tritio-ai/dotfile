#!/usr/bin/env sh
set -eu

# Delegates font refresh to the sibling dotfile-packages repo, which
# maintains the vendored font files, its own updater, and VERSIONS.org.
#
# Override with DOTFILE_PACKAGES if the packages repo lives elsewhere.
# Network proxy: export MYPROXY=host:port before running.

script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
repo_dir=$(CDPATH='' cd "$script_dir/.." && pwd -P)
. "$repo_dir/lib/packages.sh"
dotfile_delegate_package_update "$repo_dir" wezterm
