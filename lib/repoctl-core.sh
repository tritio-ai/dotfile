#!/usr/bin/env sh

# Configuration parsing and repository guards shared by repoctl commands.

validate_config_value() {
  name=$1 path=$2 environment=$3 visibility=$4 presence=$5 verify=$6
  case "$name" in ''|*[!A-Za-z0-9._-]*) fail "invalid repository name: $name" ;; esac
  case "$path" in ''|*"$tab"*|*"
"*) fail "invalid path for $name" ;; esac
  case "$environment" in ''|*[!A-Z0-9_]*) fail "invalid environment name for $name" ;; esac
  case "$visibility" in public|private) ;; *) fail "invalid visibility for $name: $visibility" ;; esac
  case "$presence" in required|optional) ;; *) fail "invalid presence for $name: $presence" ;; esac
  case "$verify" in ''|/*|../*|*/../*|*"$tab"*) fail "unsafe verification path for $name: $verify" ;; esac
}

environment_value() {
  variable=$1
  eval "printf '%s' \"\${$variable-}\""
}

resolve_repo_path() {
  configured_path=$1 environment=$2
  override=$(environment_value "$environment")
  path=${override:-$configured_path}
  case "$path" in /*) candidate=$path ;; *) candidate=$(dirname "$config")/$path ;; esac
  if [ -d "$candidate" ]; then
    (CDPATH='' cd "$candidate" && pwd -P)
  else
    printf '%s\n' "$candidate"
  fi
}

remote_url_is_allowed() {
  url=$1
  [ "${REPOCTL_ALLOW_LOCAL_REMOTES:-0}" = 1 ] && return 0
  printf '%s\n' "$url" | grep -Eq \
    '^ssh://[^[:space:]]+$|^([A-Za-z0-9._-]+@)?[A-Za-z0-9._-]+:[^[:space:]]+$'
}

public_secret_scan() {
  repo=$1
  command -v rg >/dev/null 2>&1 || {
    printf 'ERROR: rg is required for the public-tree secret scan\n' >&2
    return 1
  }
  output=$(mktemp "${TMPDIR:-/tmp}/repoctl-secret-scan.XXXXXX")
  scan_result=0
  (cd "$repo" && rg -n -I \
    -e 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-|AIza[0-9A-Za-z_-]{20,}|-----BEGIN .*PRIVATE KEY-----|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{6,}' \
    . --hidden --glob '!.git/**' --glob '!verify.sh' --glob '!**/verify.sh' \
    --glob '!repoctl.sh' --glob '!**/repoctl.sh' --glob '!repoctl-core.sh' \
    --glob '!**/repoctl-core.sh' --glob '!*.sig') >"$output" 2>/dev/null || scan_result=$?
  if [ "$scan_result" -eq 0 ]; then
    cat "$output" >&2
    rm -f "$output"
    return 1
  fi
  rm -f "$output"
  [ "$scan_result" -eq 1 ] || {
    printf 'ERROR: public-tree secret scan could not complete\n' >&2
    return 1
  }
  if git -C "$repo" ls-files |
    grep -E '(^|/)(authinfo|credentials|private[-_.]?key)(\.|$)|\.(pem|p12|pfx|key|gpg)$' >/dev/null; then
    return 1
  fi
  return 0
}

validate_repo() {
  name=$1 repo=$2 visibility=$3 presence=$4 require_all=$5
  if [ ! -e "$repo/.git" ]; then
    if [ "$presence" = optional ] && [ "$require_all" = 0 ]; then
      log "SKIP $name: absent at $repo"
      return 2
    fi
    printf 'ERROR: %s repository absent at %s\n' "$name" "$repo" >&2
    return 1
  fi
  actual=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || {
    printf 'ERROR: %s is not a Git worktree: %s\n' "$name" "$repo" >&2
    return 1
  }
  [ "$actual" = "$repo" ] || {
    printf 'ERROR: %s resolves inside another worktree: %s\n' "$name" "$actual" >&2
    return 1
  }
  git -C "$repo" show-ref --verify --quiet refs/heads/main || {
    printf 'ERROR: %s has no local main branch\n' "$name" >&2
    return 1
  }
  remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null) || {
    printf 'ERROR: %s has no origin remote\n' "$name" >&2
    return 1
  }
  remote_url_is_allowed "$remote_url" || {
    printf 'ERROR: %s origin is not SSH: %s\n' "$name" "$remote_url" >&2
    return 1
  }
  GIT_TERMINAL_PROMPT=0 git -C "$repo" ls-remote --exit-code --heads origin refs/heads/main >/dev/null || {
    printf 'ERROR: %s origin/main is unavailable\n' "$name" >&2
    return 1
  }
  if [ "$visibility" = public ] && ! public_secret_scan "$repo"; then
    printf 'ERROR: %s public-tree secret scan failed\n' "$name" >&2
    return 1
  fi
  status=$(git -C "$repo" status --porcelain)
  if [ -n "$status" ]; then state=dirty; else state=clean; fi
  commits=$(git -C "$repo" rev-list --count main)
  log "OK   $name: $state, $commits local commit(s), $remote_url"
}

walk_config() {
  operation=$1 require_all=$2 failures=0
  [ -r "$config" ] || fail "repository config not readable: $config"
  while IFS="$tab" read -r name path environment visibility presence verify extra; do
    [ "$name" = name ] && continue
    [ -n "$name" ] || continue
    [ -z "${extra:-}" ] || fail "too many fields in repository config row: $name"
    validate_config_value "$name" "$path" "$environment" "$visibility" "$presence" "$verify"
    repo=$(resolve_repo_path "$path" "$environment")
    result=0
    "$operation" "$name" "$repo" "$visibility" "$presence" "$verify" "$require_all" || result=$?
    if [ "$result" -ne 0 ]; then
      [ "$result" -eq 2 ] || failures=$((failures + 1))
    fi
  done < "$config"
  [ "$failures" -eq 0 ] || fail "$failures repository operation(s) failed"
}

release_id_from_dir() {
  release_dir=$1
  [ -r "$release_dir/release.id" ] || fail "not a prepared release: $release_dir"
  release_id=$(sed -n '1p' "$release_dir/release.id")
  case "$release_id" in ''|*[!A-Za-z0-9._-]*) fail "invalid release id" ;; esac
  printf '%s\n' "$release_id"
}

manifest_operation() {
  action=$1 release_dir=$2 manifest=$2/manifest.tsv failures=0
  [ -r "$manifest" ] || fail "missing release manifest: $manifest"
  awk -F '\t' '
    NR == 1 {
      if ($0 != "name\tpath\tvisibility\tremote_head\tsnapshot\ttree\tremote_url") exit 1
      next
    }
    NF != 7 || seen_name[$1]++ || seen_path[$2]++ || seen_remote[$7]++ { exit 1 }
  ' "$manifest" || fail "invalid or duplicate release manifest entry"
  while IFS="$tab" read -r name repo visibility remote_head snapshot tree remote_url extra; do
    [ "$name" = name ] && continue
    [ -n "$name" ] || continue
    [ -z "${extra:-}" ] || fail "invalid manifest row: $name"
    case "$name" in ''|*[!A-Za-z0-9._-]*) fail "invalid manifest repository: $name" ;; esac
    case "$visibility" in public|private) ;; *) fail "invalid manifest visibility: $visibility" ;; esac
    case "$remote_head:$snapshot:$tree" in *[!0-9a-f:]*) fail "invalid object id in manifest: $name" ;; esac
    remote_url_is_allowed "$remote_url" || fail "non-SSH remote in manifest: $name"
    if ! "$action" "$release_dir" "$name" "$repo" "$visibility" "$remote_head" "$snapshot" "$tree" "$remote_url"; then
      failures=$((failures + 1))
      break
    fi
  done < "$manifest"
  [ "$failures" -eq 0 ] || fail "$action failed"
}
