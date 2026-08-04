#!/usr/bin/env bash
# Set Jekyll env vars for CI builds (append to GITHUB_ENV when present).
set -eu

append_env() {
  local key="$1"
  local value="$2"
  if [ -n "${GITHUB_ENV:-}" ]; then
    printf '%s=%s\n' "$key" "$value" >>"$GITHUB_ENV"
  fi
  export "$key=$value"
}

append_env JEKYLL_INCREMENTAL_EPISODE_PAGES 1

BEFORE="${GITHUB_EVENT_BEFORE:-}"
AFTER="${GITHUB_SHA:-HEAD}"
if [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
  BEFORE="HEAD~1"
fi

CHANGED=$(git diff --name-only "$BEFORE" "$AFTER" 2>/dev/null || true)

if echo "$CHANGED" | grep -q '^[_]plugins/'; then
  append_env REBUILD_ALL_EPISODE_PAGES 1
fi

if echo "$CHANGED" | grep -qE '^[_]layouts/episode\.html$|^[_]includes/episode-'; then
  append_env REBUILD_ALL_EPISODE_PAGES 1
fi

SLUGS=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ -f "$file" ] || continue
  slug=$(grep -E '^url_slug:' "$file" | head -1 | sed -E 's/^url_slug:[[:space:]]*"?([^"]*)"?/\1/' | tr -d ' ')
  if [ -z "$slug" ]; then
    base=$(basename "$file" .md)
    slug=$(echo "$base" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/-md$//')
  fi
  [ -n "$slug" ] || continue
  if [ -n "$SLUGS" ]; then
    SLUGS="${SLUGS},${slug}"
  else
    SLUGS="$slug"
  fi
done <<EOF
$(echo "$CHANGED" | grep '^_posts/podcasts/' || true)
EOF

if [ -n "$SLUGS" ]; then
  append_env CHANGED_PODCAST_SLUGS "$SLUGS"
fi
