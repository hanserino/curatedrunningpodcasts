#!/usr/bin/env bash
# Generate episode HTML from committed _data without RSS fetch or show-note resanitize.
set -eu

EPISODE_PAGES_PER_PODCAST="${EPISODE_PAGES_PER_PODCAST:-10}"

echo "==> YouTube episode matching"
JEKYLL_ENV=production YOUTUBE_MATCH=1 EPISODE_PAGES_BUILD=1 \
  bundle exec ruby tools/match-youtube-episodes.rb

JEKYLL_ENV=production EPISODE_PAGES_BUILD=1 SKIP_DATA_RESANITIZE=1 YOUTUBE_MATCH=1 \
  EPISODE_PAGES_PER_PODCAST="$EPISODE_PAGES_PER_PODCAST" \
  bash tools/ci-jekyll-build.sh docs
