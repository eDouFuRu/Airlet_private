#!/bin/bash
set -euo pipefail
umask 022

# Publish the source snapshot and the disk image to the public repository.
#
# This is the only script in the repo that talks to GitHub. It prints exactly what
# it is about to make public and refuses to do it without --yes.
#
# Usage:
#   bash scripts/publish-release.sh [--repo owner/name] [--snapshot DIR] [--dmg PATH] [--yes]

ISLAND_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ISLAND_PROJECT_ROOT/scripts/lib/local-signing.sh"

ISLAND_REPOSITORY='eDouFuRu/notch-island'
ISLAND_SNAPSHOT="$ISLAND_PROJECT_ROOT/dist/public-snapshot"
ISLAND_IMAGE=''
ISLAND_CONFIRMED=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) ISLAND_REPOSITORY="${2:-}"; shift 2 ;;
    --snapshot) ISLAND_SNAPSHOT="${2:-}"; shift 2 ;;
    --dmg) ISLAND_IMAGE="${2:-}"; shift 2 ;;
    --yes) ISLAND_CONFIRMED=true; shift ;;
    *) island_die "Usage: $0 [--repo owner/name] [--snapshot DIR] [--dmg PATH] [--yes]" ;;
  esac
done

/usr/bin/env command -v gh >/dev/null || island_die 'gh is not installed: brew install gh'
gh auth status >/dev/null 2>&1 || island_die 'gh is not authenticated: gh auth login'
[[ -d "$ISLAND_SNAPSHOT/.git" ]] || island_die "No snapshot repository at $ISLAND_SNAPSHOT (run scripts/make-public-snapshot.sh)"

ISLAND_TAG="$(/usr/bin/git -C "$ISLAND_SNAPSHOT" describe --tags --exact-match HEAD)" ||
  island_die 'The snapshot HEAD carries no version tag.'
ISLAND_VERSION="${ISLAND_TAG#v}"
[[ -n "$ISLAND_IMAGE" ]] || ISLAND_IMAGE="$ISLAND_PROJECT_ROOT/dist/NotchIsland-$ISLAND_VERSION.dmg"
ISLAND_NOTES="$ISLAND_PROJECT_ROOT/dist/RELEASE-NOTES-$ISLAND_VERSION.md"
[[ -f "$ISLAND_IMAGE" ]] || island_die "No disk image at $ISLAND_IMAGE (run scripts/package-release.sh)"
[[ -f "$ISLAND_NOTES" ]] || island_die "No release notes at $ISLAND_NOTES"

printf 'About to publish, PUBLICLY and irreversibly:\n\n'
printf '  repository  https://github.com/%s (public)\n' "$ISLAND_REPOSITORY"
printf '  source      %s files, single commit %s, tag %s\n' \
  "$(/usr/bin/git -C "$ISLAND_SNAPSHOT" ls-files | /usr/bin/wc -l | /usr/bin/tr -d ' ')" \
  "$(/usr/bin/git -C "$ISLAND_SNAPSHOT" rev-parse --short HEAD)" "$ISLAND_TAG"
printf '  asset       %s (%s)\n' "$(basename "$ISLAND_IMAGE")" "$(/usr/bin/du -h "$ISLAND_IMAGE" | /usr/bin/awk '{print $1}')"
printf '  sha256      %s\n' "$(/usr/bin/shasum -a 256 "$ISLAND_IMAGE" | /usr/bin/awk '{print $1}')"
printf '  notes       %s\n\n' "$ISLAND_NOTES"

if [[ "$ISLAND_CONFIRMED" != true ]]; then
  printf 'Nothing was published. Re-run with --yes to go ahead.\n'
  exit 0
fi

if gh repo view "$ISLAND_REPOSITORY" >/dev/null 2>&1; then
  printf 'Repository already exists; pushing the new snapshot.\n'
else
  gh repo create "$ISLAND_REPOSITORY" --public \
    --description '工位充电岛 · macOS 刘海小岛应用（基于 boring.notch 的定制版，GPL-3.0）'
fi

/usr/bin/git -C "$ISLAND_SNAPSHOT" remote remove origin 2>/dev/null || true
# SSH, because that is what gh authenticated with; the HTTPS remote would ask for
# a password that no credential helper can supply.
/usr/bin/git -C "$ISLAND_SNAPSHOT" remote add origin "git@github.com:$ISLAND_REPOSITORY.git"
# Each release replaces the published snapshot: the public history is one commit
# per release by design, so this push is expected to be non-fast-forward.
/usr/bin/git -C "$ISLAND_SNAPSHOT" push --force origin main
/usr/bin/git -C "$ISLAND_SNAPSHOT" push --force origin "refs/tags/$ISLAND_TAG"

if gh release view "$ISLAND_TAG" --repo "$ISLAND_REPOSITORY" >/dev/null 2>&1; then
  gh release upload "$ISLAND_TAG" "$ISLAND_IMAGE" --repo "$ISLAND_REPOSITORY" --clobber
else
  gh release create "$ISLAND_TAG" "$ISLAND_IMAGE" --repo "$ISLAND_REPOSITORY" \
    --title "工位充电岛 $ISLAND_TAG" --notes-file "$ISLAND_NOTES"
fi

printf '\nPublished: https://github.com/%s/releases/tag/%s\n' "$ISLAND_REPOSITORY" "$ISLAND_TAG"
