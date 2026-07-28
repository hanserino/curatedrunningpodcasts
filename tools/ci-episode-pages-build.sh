#!/usr/bin/env bash
# Generate episode HTML from committed _data without RSS fetch or show-note resanitize.
set -eu

EPISODE_PAGES_PER_PODCAST="${EPISODE_PAGES_PER_PODCAST:-10}"

JEKYLL_ENV=production EPISODE_PAGES_BUILD=1 SKIP_DATA_RESANITIZE=1 \
  EPISODE_PAGES_PER_PODCAST="$EPISODE_PAGES_PER_PODCAST" \
  bash tools/ci-jekyll-build.sh docs
