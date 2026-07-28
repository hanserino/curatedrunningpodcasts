#!/usr/bin/env bash
# Feed refresh then generate missing episode pages in one workspace (single commit).
set -eu

EPISODE_PAGES_PER_PODCAST="${EPISODE_PAGES_PER_PODCAST:-10}"
RSS_FETCH_CONCURRENCY="${RSS_FETCH_CONCURRENCY:-10}"

echo "==> Feed refresh (RSS, no episode HTML)"
JEKYLL_ENV=production JEKYLL_FETCH_RSS=1 SKIP_EPISODE_PAGES=1 \
  EPISODE_PAGES_PER_PODCAST="$EPISODE_PAGES_PER_PODCAST" \
  RSS_FETCH_CONCURRENCY="$RSS_FETCH_CONCURRENCY" \
  bash tools/ci-jekyll-build.sh docs

echo "==> Episode pages (committed _data, missing HTML only)"
JEKYLL_ENV=production EPISODE_PAGES_BUILD=1 SKIP_DATA_RESANITIZE=1 \
  EPISODE_PAGES_PER_PODCAST="$EPISODE_PAGES_PER_PODCAST" \
  bash tools/ci-jekyll-build.sh docs
