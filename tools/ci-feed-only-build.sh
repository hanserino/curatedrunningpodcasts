#!/usr/bin/env bash
# RSS refresh + YouTube matching only. Episode HTML is built by ci-episode-pages-build.sh
# (triggered via episode-pages-jekyll-build.yml after this workflow succeeds).
set -eu

EPISODE_PAGES_PER_PODCAST="${EPISODE_PAGES_PER_PODCAST:-20}"
RSS_FETCH_CONCURRENCY="${RSS_FETCH_CONCURRENCY:-10}"

echo "==> Feed refresh (RSS, no episode HTML)"
# YouTube matching runs in the standalone step below; skip it during Jekyll to avoid duplicate fetches.
JEKYLL_ENV=production JEKYLL_FETCH_RSS=1 SKIP_EPISODE_PAGES=1 YOUTUBE_MATCH=0 \
  EPISODE_PAGES_PER_PODCAST="$EPISODE_PAGES_PER_PODCAST" \
  RSS_FETCH_CONCURRENCY="$RSS_FETCH_CONCURRENCY" \
  bash tools/ci-jekyll-build.sh docs

echo "==> YouTube episode matching"
JEKYLL_ENV=production YOUTUBE_MATCH=1 EPISODE_PAGES_BUILD=1 \
  bundle exec ruby tools/match-youtube-episodes.rb
