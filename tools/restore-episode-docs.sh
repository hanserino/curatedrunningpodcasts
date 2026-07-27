#!/usr/bin/env bash
# Restore episode HTML from a git ref without overwriting podcast landing pages.
set -eu

SOURCE_REF="${1:?usage: restore-episode-docs.sh <git-ref>}"
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

should_restore() {
  local path="$1"
  local rel="${path#docs/}"

  case "$rel" in
    index.html|feed.xml|sitemap.xml|robots.txt) return 1 ;;
  esac

  if [[ "$rel" == */index.html ]]; then
    local segments
    segments=$(echo "$rel" | tr '/' '\n' | grep -c . || true)
    [ "$segments" -ge 3 ]
    return
  fi

  if [[ "$rel" == *.html ]]; then
    local segments
    segments=$(echo "$rel" | tr '/' '\n' | grep -c . || true)
    [ "$segments" -ge 2 ]
    return
  fi

  return 1
}

count=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if should_restore "$path"; then
    git checkout "$SOURCE_REF" -- "$path"
    count=$((count + 1))
  fi
done < <(git ls-tree -r "$SOURCE_REF" --name-only docs/)

echo "Restored $count episode files from $SOURCE_REF."
