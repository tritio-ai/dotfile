#!/usr/bin/env sh
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_dir=$(cd "$script_dir/.." && pwd -P)
. "$repo_dir/lib/packages.sh"
dotfile_delegate_package_update "$repo_dir" emacs
