#!/usr/bin/env sh
set -eu

root_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfile-repoctl.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

create_repo() {
  name=$1
  mkdir -p "$test_root/work/$name"
  git init -q -b main "$test_root/work/$name"
  printf '%s\n' "$name" > "$test_root/work/$name/content.txt"
  printf '%s\n' '#!/usr/bin/env sh' 'set -eu' > "$test_root/work/$name/verify.sh"
  chmod +x "$test_root/work/$name/verify.sh"
  git -C "$test_root/work/$name" add content.txt verify.sh
  git -C "$test_root/work/$name" \
    -c user.name=Test -c user.email=test@example.invalid commit -q -m initial
  printf '%s\n' changed >> "$test_root/work/$name/content.txt"
  git init -q --bare "$test_root/remotes/$name.git"
  git -C "$test_root/work/$name" remote add origin "$test_root/remotes/$name.git"
  git -C "$test_root/work/$name" push -q -u origin main
}

mkdir -p "$test_root/work" "$test_root/remotes" "$test_root/state"
create_repo dotfile-packages
create_repo dotfile
create_repo vault

{
  printf 'name\tpath\tenvironment\tvisibility\tpresence\tverify\n'
  printf 'dotfile-packages\twork/dotfile-packages\tTEST_PACKAGES\tpublic\trequired\tverify.sh\n'
  printf 'dotfile\twork/dotfile\tTEST_DOTFILE\tpublic\trequired\tverify.sh\n'
  printf 'vault\twork/vault\tTEST_VAULT\tprivate\trequired\tverify.sh\n'
} > "$test_root/repos.tsv"

export REPOCTL_CONFIG="$test_root/repos.tsv"
export REPOCTL_STATE_DIR="$test_root/state"
export REPOCTL_ALLOW_LOCAL_REMOTES=1
export REPOCTL_RELEASE_ID=test-release

sh "$root_dir/repoctl.sh" check

git -C "$test_root/work/dotfile-packages" remote set-url origin https://example.invalid/public.git
if REPOCTL_ALLOW_LOCAL_REMOTES=0 sh "$root_dir/repoctl.sh" check >/dev/null 2>&1; then
  printf '%s\n' 'check unexpectedly accepted an HTTPS remote' >&2
  exit 1
fi
git -C "$test_root/work/dotfile-packages" remote set-url origin "$test_root/remotes/dotfile-packages.git"

sh "$root_dir/repoctl.sh" prepare
release=$test_root/state/test-release

REPOCTL_RELEASE_ID=test-release-2 sh "$root_dir/repoctl.sh" prepare
release_2=$test_root/state/test-release-2

snapshots_1=$(cut -f1,5 "$release/manifest.tsv")
snapshots_2=$(cut -f1,5 "$release_2/manifest.tsv")
[ "$snapshots_1" = "$snapshots_2" ]

tampered_candidate=$release_2/candidates/dotfile.git
tampered_tree=$(git -C "$tampered_candidate" rev-parse 'main^{tree}')
tampered_commit=$(printf '%s\n' tampered | git -C "$tampered_candidate" commit-tree "$tampered_tree")
git -C "$tampered_candidate" update-ref refs/heads/main "$tampered_commit"
if REPOCTL_CONFIRM=test-release-2 sh "$root_dir/repoctl.sh" publish "$release_2" >/dev/null 2>&1; then
  printf '%s\n' 'publish unexpectedly accepted a modified candidate' >&2
  exit 1
fi

while IFS="$(printf '\t')" read -r name repo visibility old snapshot tree remote; do
  [ "$name" = name ] && continue
  [ "$(git -C "$release/candidates/$name.git" rev-list --count main)" -eq 1 ]
  [ "$(git -C "$release/candidates/$name.git" rev-parse main^{tree})" = "$tree" ]
done < "$release/manifest.tsv"

if sh "$root_dir/repoctl.sh" publish "$release" >/dev/null 2>&1; then
  printf '%s\n' 'publish unexpectedly succeeded without confirmation' >&2
  exit 1
fi
REPOCTL_CONFIRM=test-release sh "$root_dir/repoctl.sh" publish "$release"
sh "$root_dir/repoctl.sh" verify-remote "$release"

for name in dotfile-packages dotfile vault; do
  [ "$(git --git-dir="$test_root/remotes/$name.git" rev-list --count main)" -eq 1 ]
done

git --git-dir="$test_root/remotes/vault.git" tag concurrent-change main
if REPOCTL_CONFIRM=rollback:test-release sh "$root_dir/repoctl.sh" rollback "$release" >/dev/null 2>&1; then
  printf '%s\n' 'rollback unexpectedly deleted a concurrently added ref' >&2
  exit 1
fi
git --git-dir="$test_root/remotes/vault.git" tag -d concurrent-change >/dev/null

REPOCTL_CONFIRM=rollback:test-release sh "$root_dir/repoctl.sh" rollback "$release"
while IFS="$(printf '\t')" read -r name repo visibility old snapshot tree remote; do
  [ "$name" = name ] && continue
  [ "$(git --git-dir="$test_root/remotes/$name.git" rev-parse main)" = "$old" ]
done < "$release/manifest.tsv"

printf '%s\n' 'repoctl integration test passed'
