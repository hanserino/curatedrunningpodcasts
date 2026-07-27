#!/usr/bin/env bash
# Run a production Jekyll build. Directory-only builds (SKIP_EPISODE_PAGES=1) write to a
# temp dir and rsync into docs/ without --delete so Jekyll's destination cleaner does not
# wipe committed episode HTML under docs/{show}/{episode}/.
set -eu

DEST="${1:-docs}"

if [ "${SKIP_EPISODE_PAGES:-0}" = "1" ]; then
  TEMP=$(mktemp -d)
  trap 'rm -rf "$TEMP"' EXIT
  bundle exec jekyll build --destination "$TEMP"
  mkdir -p "$DEST"
  rsync -a "$TEMP"/ "$DEST"/
else
  bundle exec jekyll build --destination "$DEST"
fi
