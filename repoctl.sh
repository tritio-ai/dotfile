#!/usr/bin/env sh
set -eu

root_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
config=${REPOCTL_CONFIG:-$root_dir/repos.tsv}
state_root=${REPOCTL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfile-repos/releases}
tab=$(printf '\t')

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: sh repoctl.sh COMMAND [RELEASE_DIR]

Commands:
  check                 Validate configured repositories and SSH remotes.
  verify                Run each present repository's verification script.
  prepare               Verify all repositories and build one-commit candidates.
  publish RELEASE_DIR   Force-push prepared candidates with leases.
  verify-remote DIR     Confirm each remote contains only the prepared main commit.
  rollback RELEASE_DIR  Restore remote refs from prepare-time mirror backups.

Publishing requires REPOCTL_CONFIRM=<release-id>.
Rollback requires REPOCTL_CONFIRM=rollback:<release-id>.
EOF
}

. "$root_dir/lib/repoctl-core.sh"

check_operation() {
  validate_repo "$1" "$2" "$3" "$4" "$6"
}

verify_operation() {
  name=$1 repo=$2 visibility=$3 presence=$4 verify=$5 require_all=$6
  validate_repo "$name" "$repo" "$visibility" "$presence" "$require_all" || return $?
  [ -f "$repo/$verify" ] || { printf 'ERROR: %s missing %s\n' "$name" "$verify" >&2; return 1; }
  log "==> verify $name"
  DOTFILE_PACKAGES="${DOTFILE_PACKAGES:-$(dirname "$root_dir")/dotfile-packages}" \
    DOTFILE_VAULT="${DOTFILE_VAULT:-$(dirname "$root_dir")/vault}" \
    sh "$repo/$verify"
}

create_snapshot() {
  name=$1 repo=$2 release_dir=$3
  index=$release_dir/index-$name
  candidate=$release_dir/candidates/$name.git

  GIT_INDEX_FILE="$index" git -C "$repo" read-tree --empty
  GIT_INDEX_FILE="$index" git -C "$repo" add -A -- .
  tree=$(GIT_INDEX_FILE="$index" git -C "$repo" write-tree)
  snapshot=$(
    printf 'Initial snapshot: %s\n' "$name" |
      GIT_AUTHOR_NAME='Repository Snapshot' \
      GIT_AUTHOR_EMAIL='snapshot@invalid' \
      GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' \
      GIT_COMMITTER_NAME='Repository Snapshot' \
      GIT_COMMITTER_EMAIL='snapshot@invalid' \
      GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
      git -C "$repo" commit-tree "$tree"
  )
  git init -q --bare "$candidate"
  git -C "$candidate" fetch -q "$repo" "$snapshot:refs/heads/main"
  git -C "$candidate" symbolic-ref HEAD refs/heads/main
  printf '%s\t%s\n' "$snapshot" "$tree"
}

prepare_operation() {
  name=$1 repo=$2 visibility=$3 presence=$4 verify=$5 require_all=$6
  validate_repo "$name" "$repo" "$visibility" "$presence" "$require_all" || return $?
  log "==> verify $name"
  DOTFILE_PACKAGES="${DOTFILE_PACKAGES:-$(dirname "$root_dir")/dotfile-packages}" \
    DOTFILE_VAULT="${DOTFILE_VAULT:-$(dirname "$root_dir")/vault}" \
    sh "$repo/$verify" || return 1

  remote_url=$(git -C "$repo" remote get-url origin)
  remote_head=$(GIT_TERMINAL_PROMPT=0 git -C "$repo" ls-remote --heads origin refs/heads/main | awk 'NR == 1 {print $1}')
  backup=$prepared_release/backups/$name.git
  log "==> back up remote $name"
  GIT_TERMINAL_PROMPT=0 git clone -q --mirror "$remote_url" "$backup" || return 1
  GIT_TERMINAL_PROMPT=0 git -C "$repo" ls-remote --refs origin > "$prepared_release/remote-$name.refs"

  pair=$(create_snapshot "$name" "$repo" "$prepared_release") || return 1
  snapshot=${pair%%"$tab"*}
  tree=${pair#*"$tab"}
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$repo" "$visibility" "$remote_head" "$snapshot" "$tree" "$remote_url" \
    >> "$prepared_release/manifest.tsv"
  log "READY $name: $snapshot"
}

prepare_release() {
  umask 077
  release_id=${REPOCTL_RELEASE_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}
  case "$release_id" in ''|*[!A-Za-z0-9._-]*) fail "invalid REPOCTL_RELEASE_ID" ;; esac
  prepared_release=$state_root/$release_id
  [ ! -e "$prepared_release" ] || fail "release already exists: $prepared_release"
  mkdir -p "$prepared_release/backups" "$prepared_release/candidates"
  printf '%s\n' "$release_id" > "$prepared_release/release.id"
  printf 'name\tpath\tvisibility\tremote_head\tsnapshot\ttree\tremote_url\n' > "$prepared_release/manifest.tsv"
  export prepared_release
  walk_config prepare_operation 1
  rm -f "$prepared_release"/index-*
  log "prepared release: $prepared_release"
  log "publish with: REPOCTL_CONFIRM=$release_id sh repoctl.sh publish $prepared_release"
}

publish_operation() {
  release_dir=$1 name=$2 repo=$3 visibility=$4 expected=$5 snapshot=$6 tree=$7 remote_url=$8
  log "==> publish $name"
  GIT_TERMINAL_PROMPT=0 git -C "$release_dir/candidates/$name.git" push \
    --force-with-lease="refs/heads/main:$expected" "$remote_url" \
    "refs/heads/main:refs/heads/main"
  printf '%s\t%s\n' "$name" "$snapshot" >> "$release_dir/published.tsv"
}

publish_preflight_operation() {
  release_dir=$1 name=$2 repo=$3 visibility=$4 expected=$5 snapshot=$6 tree=$7 remote_url=$8
  current_url=$(git -C "$repo" remote get-url origin 2>/dev/null) || return 1
  [ "$current_url" = "$remote_url" ] || { printf 'ERROR: %s origin changed\n' "$name" >&2; return 1; }
  current_refs=$(GIT_TERMINAL_PROMPT=0 git -C "$repo" ls-remote --refs origin)
  current=$(printf '%s\n' "$current_refs" | awk '$2 == "refs/heads/main" {print $1}')
  [ "$current" = "$expected" ] || {
    printf 'ERROR: %s origin/main changed since prepare (%s != %s)\n' "$name" "$current" "$expected" >&2
    return 1
  }
  ref_count=$(printf '%s\n' "$current_refs" | awk 'NF {n++} END {print n+0}')
  [ "$ref_count" -eq 1 ] || {
    printf 'ERROR: %s remote has refs other than main; remove them explicitly before publish\n' "$name" >&2
    return 1
  }
  candidate=$release_dir/candidates/$name.git
  [ -d "$candidate" ] || {
    printf 'ERROR: %s prepared candidate is missing\n' "$name" >&2
    return 1
  }
  git -C "$candidate" fsck --strict --no-dangling >/dev/null 2>&1 || {
    printf 'ERROR: %s prepared candidate is corrupt\n' "$name" >&2
    return 1
  }
  candidate_head=$(git -C "$candidate" rev-parse refs/heads/main 2>/dev/null) || return 1
  candidate_tree=$(git -C "$candidate" rev-parse "refs/heads/main^{tree}" 2>/dev/null) || return 1
  candidate_parents=$(git -C "$candidate" rev-list --parents -n 1 refs/heads/main | awk '{print NF-1}')
  [ "$candidate_head" = "$snapshot" ] && [ "$candidate_tree" = "$tree" ] &&
    [ "$candidate_parents" -eq 0 ] || {
      printf 'ERROR: %s prepared candidate differs from its manifest\n' "$name" >&2
      return 1
    }
  log "OK   $name publish preflight"
}

verify_remote_operation() {
  release_dir=$1 name=$2 repo=$3 visibility=$4 expected=$5 snapshot=$6 tree=$7 remote_url=$8
  refs=$(GIT_TERMINAL_PROMPT=0 git -C "$repo" ls-remote --refs origin)
  count=$(printf '%s\n' "$refs" | awk 'NF {n++} END {print n+0}')
  actual=$(printf '%s\n' "$refs" | awk '$2 == "refs/heads/main" {print $1}')
  [ "$count" -eq 1 ] && [ "$actual" = "$snapshot" ] || {
    printf 'ERROR: %s remote is not the prepared one-commit main\n' "$name" >&2
    return 1
  }
  parents=$(git -C "$release_dir/candidates/$name.git" rev-list --parents -n 1 "$snapshot" | awk '{print NF-1}')
  [ "$parents" -eq 0 ] || { printf 'ERROR: %s snapshot has parents\n' "$name" >&2; return 1; }
  log "OK   $name remote: one root commit $snapshot"
}

rollback_operation() {
  release_dir=$1 name=$2 repo=$3 visibility=$4 expected=$5 snapshot=$6 tree=$7 remote_url=$8
  log "==> rollback $name"
  GIT_TERMINAL_PROMPT=0 git -C "$release_dir/backups/$name.git" push --mirror "$remote_url"
}

rollback_preflight_operation() {
  release_dir=$1 name=$2 repo=$3 visibility=$4 expected=$5 snapshot=$6 tree=$7 remote_url=$8
  current_url=$(git -C "$repo" remote get-url origin 2>/dev/null) || return 1
  [ "$current_url" = "$remote_url" ] || {
    printf 'ERROR: %s origin changed\n' "$name" >&2
    return 1
  }
  current_refs=$(GIT_TERMINAL_PROMPT=0 git -C "$repo" ls-remote --refs origin)
  current=$(printf '%s\n' "$current_refs" | awk '$2 == "refs/heads/main" {print $1}')
  ref_count=$(printf '%s\n' "$current_refs" | awk 'NF {n++} END {print n+0}')
  [ "$ref_count" -eq 1 ] && [ "$current" = "$snapshot" ] || {
    printf 'ERROR: %s remote changed after publish; refusing rollback\n' "$name" >&2
    return 1
  }
  [ -d "$release_dir/backups/$name.git" ] || {
    printf 'ERROR: %s mirror backup is missing\n' "$name" >&2
    return 1
  }
  log "OK   $name rollback preflight"
}

command=${1:-}
case "$command" in
  check) [ "$#" -eq 1 ] || fail "check takes no arguments"; walk_config check_operation 0 ;;
  verify) [ "$#" -eq 1 ] || fail "verify takes no arguments"; walk_config verify_operation 0 ;;
  prepare) [ "$#" -eq 1 ] || fail "prepare takes no arguments"; prepare_release ;;
  publish)
    [ "$#" -eq 2 ] || fail "publish requires RELEASE_DIR"
    id=$(release_id_from_dir "$2")
    [ "${REPOCTL_CONFIRM:-}" = "$id" ] || fail "set REPOCTL_CONFIRM=$id to publish"
    printf 'name\tsnapshot\n' > "$2/published.tsv"
    manifest_operation publish_preflight_operation "$2"
    manifest_operation publish_operation "$2"
    manifest_operation verify_remote_operation "$2"
    ;;
  verify-remote) [ "$#" -eq 2 ] || fail "verify-remote requires RELEASE_DIR"; manifest_operation verify_remote_operation "$2" ;;
  rollback)
    [ "$#" -eq 2 ] || fail "rollback requires RELEASE_DIR"
    id=$(release_id_from_dir "$2")
    [ "${REPOCTL_CONFIRM:-}" = "rollback:$id" ] || fail "set REPOCTL_CONFIRM=rollback:$id to rollback"
    manifest_operation rollback_preflight_operation "$2"
    manifest_operation rollback_operation "$2"
    ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
