#!/usr/bin/env sh
set -eu

repo_dir=$(cd "$(dirname "$0")" && pwd -P)
. "$repo_dir/lib/packages.sh"
packages_root=$(dotfile_packages_root "$repo_dir")

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

verify_shell_syntax() {
  find "$repo_dir" -type f -name '*.sh' -print |
    while IFS= read -r file; do
      sh -n "$file"
    done
}

verify_public_tree() {
  command -v rg >/dev/null 2>&1 || fail "rg is required for the public-tree secret scan"
  scan_file=$(mktemp "${TMPDIR:-/tmp}/dotfile-secret-scan.XXXXXX") ||
    fail "could not create secret scan file"
  scan_result=0
  (cd "$repo_dir" && rg -n -I \
    -e 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-|AIza[0-9A-Za-z_-]{20,}|-----BEGIN .*PRIVATE KEY-----|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{6,}' \
    . --hidden --glob '!.git/**' --glob '!verify.sh' --glob '!**/verify.sh' \
    --glob '!repoctl.sh' --glob '!**/repoctl.sh' --glob '!lib/repoctl-core.sh' \
    --glob '!**/repoctl-core.sh' \
    ) >"$scan_file" 2>/dev/null || scan_result=$?
  if [ "$scan_result" -eq 0 ]; then
    cat "$scan_file" >&2
    rm -f "$scan_file"
    fail "credential-like material found in public dotfile files"
  fi
  rm -f "$scan_file"
  [ "$scan_result" -eq 1 ] || fail "public-tree secret scan could not complete"
  if git -C "$repo_dir" ls-files |
    grep -E '(^|/)(authinfo|credentials|private[-_.]?key)(\.|$)|\.(pem|p12|pfx|key|gpg)$' >/dev/null; then
    fail "sensitive filename is tracked in the public dotfile tree"
  fi
}

verify_package_repo() {
  if [ ! -d "$packages_root/.git" ]; then
    log "skipping package-dependent checks: dotfile-packages absent at $packages_root"
    return 2
  fi
  [ -x "$packages_root/verify.sh" ] || fail "missing $packages_root/verify.sh"
  (cd "$packages_root" && sh ./verify.sh)
}

verify_emacs() {
  if command -v emacs >/dev/null 2>&1; then
    DOTFILE_PACKAGES="$packages_root" sh "$repo_dir/emacs/test-batch.sh"
  else
    log "skipping Emacs smoke test: emacs is not installed"
  fi
}

verify_repoctl() {
  sh "$repo_dir/test-repoctl.sh"
}

verify_shell_syntax
verify_public_tree
packages_verified=0
verify_package_repo && packages_verified=1 || result=$?
if [ "${result:-0}" -ne 0 ] && [ "${result:-0}" -ne 2 ]; then
  exit "$result"
fi
if [ "$packages_verified" -eq 1 ]; then
  verify_emacs
fi
verify_repoctl
if [ "$packages_verified" -eq 1 ]; then
  log "dotfile verification passed"
else
  log "dotfile verification passed; package-dependent checks were skipped"
fi
