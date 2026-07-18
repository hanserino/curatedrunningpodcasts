#!/usr/bin/env bash
# Push source changes with a production Jekyll build, retrying when scheduled CI
# commits land on origin/main first (avoids merge conflicts in generated docs/).
#
# Usage:
#   bash tools/local-push.sh "Your commit message"
#
# Options (env):
#   LOCAL_PUSH_FETCH_RSS=1  — fetch all RSS feeds during build (slow; usually leave off).
#                           Hourly CI refreshes episode data; local pushes ship source + assets.
#   MAX_ATTEMPTS=5          — push retries after reset/rebuild.
#
set -eu

COMMIT_MSG="${1:?usage: local-push.sh \"commit message\"}"
BRANCH="${BRANCH:-main}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"
PATCH_FILE="${TMPDIR:-/tmp}/brp-local-push.$$.patch"

cleanup() {
  rm -f "$PATCH_FILE"
}
trap cleanup EXIT

rebuild_site() {
  if [ "${LOCAL_PUSH_FETCH_RSS:-0}" = "1" ]; then
    echo "Building with RSS fetch (this may take several minutes)..."
    JEKYLL_ENV=production JEKYLL_FETCH_RSS=1 bundle exec jekyll build --destination docs
  else
    echo "Building for production (using committed episode data; no RSS fetch)..."
    JEKYLL_ENV=production bundle exec jekyll build --destination docs
  fi
}

save_source_patch() {
  git fetch origin "$BRANCH"
  git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
    git add -N "$f"
  done
  git diff "origin/${BRANCH}" -- . \
    ':(exclude)docs' \
    ':(exclude)_data/latest_podcast_episodes.yml' \
    >"$PATCH_FILE" || true

  if [ ! -s "$PATCH_FILE" ]; then
    echo "No source changes relative to origin/${BRANCH} (excluding docs/ and _data/latest_podcast_episodes.yml)."
    exit 1
  fi
}

stage_for_commit() {
  git add -A
  if [ "${LOCAL_PUSH_FETCH_RSS:-0}" != "1" ]; then
    git restore --staged _data/latest_podcast_episodes.yml 2>/dev/null || true
    git checkout -- _data/latest_podcast_episodes.yml 2>/dev/null || true
  fi
}

save_source_patch

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "Push attempt ${attempt}/${MAX_ATTEMPTS}..."
  git fetch origin "$BRANCH"
  git reset --hard "origin/${BRANCH}"
  git apply "$PATCH_FILE"
  rebuild_site
  stage_for_commit

  if git diff --staged --quiet; then
    echo "No changes to commit after build."
    exit 0
  fi

  git commit -m "$COMMIT_MSG"

  if git push origin "HEAD:refs/heads/${BRANCH}"; then
    echo "Push succeeded on attempt ${attempt}."
    exit 0
  fi

  echo "Push rejected (origin moved, likely CI RSS rebuild); retrying from fresh origin/${BRANCH}."
done

echo "Failed to push after ${MAX_ATTEMPTS} attempts."
exit 1
