#!/usr/bin/env sh
set -eu

root_dir=$(cd "$(dirname "$0")" && pwd -P)

log() {
  printf '%s\n' "$*"
}

list_modules() {
  find "$root_dir" -mindepth 2 -maxdepth 2 -name update.sh -print |
    while IFS= read -r path; do
      module_dir=${path%/update.sh}
      basename "$module_dir"
    done |
    sort
}

usage() {
  log "Usage: sh update.sh all | <module> [module...]"
  log ""
  log "Available update modules:"
  list_modules | sed 's/^/  /'
}

run_module() {
  module=$1

  case "$module" in
    ""|.*|*/*)
      log "Invalid module name: $module"
      return 1
      ;;
  esac

  script="$root_dir/$module/update.sh"
  if [ ! -f "$script" ]; then
    log "No update script for module: $module"
    return 1
  fi

  log "==> update $module"
  (cd "$root_dir/$module" && sh ./update.sh)
}

run_all() {
  modules=$(list_modules)
  if [ -z "$modules" ]; then
    log "No update modules found."
    return 1
  fi

  for module in $modules; do
    run_module "$module"
  done
}

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

if [ "$1" = "all" ]; then
  if [ "$#" -ne 1 ]; then
    log "The all target cannot be combined with module names."
    exit 2
  fi
  run_all
  exit 0
fi

for module in "$@"; do
  run_module "$module"
done
