#!/usr/bin/env bash
# Fast production build: directory pages + podcast players only.
# Uses committed _data; no RSS bulk fetch, no YouTube matching, no episode HTML.
set -eu

JEKYLL_ENV=production SKIP_EPISODE_PAGES=1 YOUTUBE_MATCH=0 \
  bash tools/ci-jekyll-build.sh docs
