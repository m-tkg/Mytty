#!/bin/sh

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

# Matches what ApplicationVersion (Sources/MyTTYApp/ApplicationUpdate.swift)
# can parse, so a tag this script accepts is always resolvable by the
# in-app updater: MAJOR.MINOR.PATCH, optionally followed by a dot-separated
# pre-release suffix such as -beta.1 or -rc.2.
version=${1:-}
if ! printf '%s\n' "$version" \
    | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'; then
    printf 'error: invalid release version: %s\n' "${version:-<empty>}" >&2
    exit 1
fi
tag="v$version"
case "$version" in
    *-*)
        kind='pre-release'
        ;;
    *)
        kind='release'
        ;;
esac

if ! git diff --quiet || ! git diff --cached --quiet \
    || [ -n "$(git status --porcelain)" ]; then
    printf 'error: commit or remove all working tree changes before release\n' >&2
    exit 1
fi

branch=$(git branch --show-current)
if [ "$branch" != main ]; then
    printf 'error: releases must be created from main (current: %s)\n' "$branch" >&2
    exit 1
fi

git fetch origin main --tags
if ! git merge-base --is-ancestor origin/main HEAD; then
    printf 'error: local main has diverged from origin/main; rebase or merge first\n' >&2
    exit 1
fi
if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
    printf 'error: tag already exists locally: %s\n' "$tag" >&2
    exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    printf 'error: tag already exists on origin: %s\n' "$tag" >&2
    exit 1
fi

swift test
Tests/ReleasePackagingTests.sh

printf 'Tagging %s as a GitHub %s\n' "$tag" "$kind"
git push origin main
git tag -a "$tag" -m "Release $tag"
git push origin "$tag"

printf 'Release workflow triggered for %s (%s)\n' "$tag" "$kind"
printf 'Track it with: gh run watch\n'
