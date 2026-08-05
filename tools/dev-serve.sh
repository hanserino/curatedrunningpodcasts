#!/usr/bin/env bash
# Fast local preview: committed episode data, no RSS, no episode HTML, no bulk resanitize.
#
# Usage:
#   bash tools/dev-serve.sh
#   bash tools/dev-serve.sh --port 4001
#
set -eu

export JEKYLL_ENV=development
export SKIP_EPISODE_PAGES=1
export SKIP_DATA_RESANITIZE=1

exec bundle exec jekyll serve \
  --destination /tmp/curatedrunningpodcasts-dev \
  --incremental \
  --force-polling \
  "$@"
