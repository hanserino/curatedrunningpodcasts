# frozen_string_literal: true

# Merge episodes_by_feed metadata (descriptions, duration, slugs) into directory
# feed items on every build so templates can use show-note snippets without a full RSS run.
class LatestEpisodesDirectoryEnrich < Jekyll::Generator
  safe true
  priority :high

  def generate(site)
    payload = site.data["latest_podcast_episodes"]
    return unless payload.is_a?(Hash)

    items = payload["items"]
    episodes_by_feed = payload["episodes_by_feed"]
    return unless items.is_a?(Array) && episodes_by_feed.is_a?(Hash)

    LatestPodcastEpisodes.reconcile_directory_items!(items, episodes_by_feed)
  end
end
