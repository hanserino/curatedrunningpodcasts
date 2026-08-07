#!/usr/bin/env bash
# Generate episode HTML from committed _data without RSS fetch. Show notes are
# re-sanitized per episode during page generation (see prepare_episode).
set -eu

EPISODE_PAGES_PER_PODCAST="${EPISODE_PAGES_PER_PODCAST:-20}"
EPISODE_PAGES_MAX_NEW="${EPISODE_PAGES_MAX_NEW:-0}"

echo "==> YouTube episode matching"
JEKYLL_ENV=production YOUTUBE_MATCH=1 EPISODE_PAGES_BUILD=1 \
  bundle exec ruby tools/match-youtube-episodes.rb

export YOUTUBE_PREMATCHED=1

JEKYLL_ENV=production EPISODE_PAGES_BUILD=1 SKIP_DATA_RESANITIZE=1 YOUTUBE_MATCH=1 \
  EPISODE_PAGES_PER_PODCAST="$EPISODE_PAGES_PER_PODCAST" \
  EPISODE_PAGES_MAX_NEW="$EPISODE_PAGES_MAX_NEW" \
  bash tools/ci-jekyll-build.sh docs
