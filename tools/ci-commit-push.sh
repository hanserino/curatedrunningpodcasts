#!/usr/bin/env bash
# Commit Jekyll build outputs and push, retrying with a fresh rebuild when another
# workflow wins the race to origin (avoids rebase conflicts in generated docs/).
set -eu

COMMIT_MSG="${1:?usage: ci-commit-push.sh \"commit message\"}"
BRANCH="${BRANCH:-main}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

stage_build_outputs() {
  git add _data/latest_podcast_episodes.yml media
  if [ "${SKIP_EPISODE_PAGES:-0}" = "1" ]; then
    git add --ignore-removal -A docs
  else
    git add -A docs
  fi
}

discard_local_noise() {
  git restore .bundle/config 2>/dev/null || true
  git restore .
}

rebuild_site() {
  npm run optimize-media
  if [ "${CI_FETCH_RSS:-0}" = "1" ]; then
    JEKYLL_ENV=production JEKYLL_FETCH_RSS=1 \
      SKIP_EPISODE_PAGES="${SKIP_EPISODE_PAGES:-0}" \
      EPISODE_PAGES_PER_PODCAST="${EPISODE_PAGES_PER_PODCAST:-25}" \
      RSS_FETCH_CONCURRENCY="${RSS_FETCH_CONCURRENCY:-8}" \
      bash tools/ci-jekyll-build.sh docs
  else
    JEKYLL_ENV=production SKIP_EPISODE_PAGES="${SKIP_EPISODE_PAGES:-1}" \
      bash tools/ci-jekyll-build.sh docs
  fi
}

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  git fetch origin "$BRANCH"

  if [ "$attempt" -gt 1 ]; then
    echo "Attempt ${attempt}: syncing to origin/${BRANCH} and rebuilding..."
    git reset --hard "origin/${BRANCH}"
    rebuild_site
  fi

  stage_build_outputs
  if git diff --staged --quiet; then
    echo "No changes; skipping commit."
    exit 0
  fi

  git commit -m "$COMMIT_MSG"
  discard_local_noise

  if git push origin "HEAD:refs/heads/${BRANCH}"; then
    echo "Push succeeded on attempt ${attempt}."
    exit 0
  fi

  echo "Push rejected on attempt ${attempt}; resetting to origin/${BRANCH}."
  git reset --hard "origin/${BRANCH}"
done

echo "Failed to push after ${MAX_ATTEMPTS} attempts."
exit 1
