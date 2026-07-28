#!/usr/bin/env bash
# Run a production Jekyll build. Builds targeting docs/ write to a temp dir and rsync
# into docs/ without --delete so Jekyll's destination cleaner does not wipe committed
# episode HTML under docs/{show}/{episode}/ that incremental mode skips regenerating.
set -eu

DEST="${1:-docs}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ABS_DEST=$(cd "$ROOT" && mkdir -p "$DEST" && cd "$DEST" && pwd)

if [ "$ABS_DEST" = "$ROOT/docs" ]; then
  TEMP=$(mktemp -d)
  trap 'rm -rf "$TEMP"' EXIT
  export EPISODE_PAGE_CHECK_DIR="$ROOT/docs"
  bundle exec jekyll build --destination "$TEMP"
  rsync -a "$TEMP"/ "$ABS_DEST"/
else
  bundle exec jekyll build --destination "$DEST"
fi
