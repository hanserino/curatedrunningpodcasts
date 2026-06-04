# frozen_string_literal: true

# Generates a static page per RSS episode under /{podcast-slug}/{episode-title-slug}/
# using episodes_by_feed from LatestPodcastEpisodes (production RSS or committed YAML).

class PodcastEpisodePage < Jekyll::Page
  def initialize(site, base, podcast_doc, episode, episode_slug)
    @site = site
    @base = base
    podcast_slug = podcast_doc.data["slug"].to_s
    @dir = podcast_slug
    @name = "#{episode_slug}.html"

    permalink = LatestPodcastEpisodes.episode_page_path(podcast_slug, episode_slug)

    redirects = []
    legacy_long = episode["episode_uid"].to_s.strip
    if legacy_long != "" && legacy_long != episode_slug
      redirects << "/#{podcast_slug}/episodes/#{legacy_long}.html"
    end

    legacy_numbered = episode["legacy_numbered_slug"].to_s.strip
    if legacy_numbered != "" && legacy_numbered != episode_slug
      redirects << "/#{podcast_slug}/#{legacy_numbered}/"
      redirects << "/#{podcast_slug}/#{legacy_numbered}.html"
    end

    description_html = LatestPodcastEpisodes.sanitize_episode_description_html(
      episode["description_html"]
    )
    description_plain =
      if description_html.empty?
        ""
      else
        LatestPodcastEpisodes.description_plain_from_html(description_html)
      end

    episode_title = episode["episode_title"].to_s.strip
    podcast_title = podcast_doc.data["title"].to_s.strip
    seo_description =
      if description_plain.empty?
        "Listen to \"#{episode_title}\" from #{podcast_title} on Best Running Podcasts."
      else
        snippet = description_plain.length > 200 ? "#{description_plain[0, 200].strip}…" : description_plain
        "Listen to \"#{episode_title}\" from #{podcast_title}. #{snippet}"
      end

    self.data = {
      "layout" => "episode",
      "category" => "podcast_episode",
      "sitemap" => podcast_doc.data["not_running_related"] != true,
      "title" => episode["episode_title"],
      "episode_title" => episode["episode_title"],
      "episode_slug" => episode_slug,
      "episode_key" => episode_slug,
      "episode_url" => episode["episode_url"],
      "audio_url" => episode["audio_url"],
      "published_at" => episode["published_at"],
      "description_html" => description_html,
      "description_plain" => description_plain,
      "seo_description" => seo_description,
      "podcast_title" => podcast_doc.data["title"],
      "podcast_url" => podcast_doc.url,
      "podcast_slug" => podcast_slug,
      "cover_image" => podcast_doc.data["cover_image"],
      "episode_image_url" => episode["episode_image_url"].to_s.strip,
      "rss_feed" => podcast_doc.data["rss_feed"],
      "tags" => podcast_doc.data["tags"],
      "language" => podcast_doc.data["language"],
      "date" => episode["published_at"],
      "episode_page_url" => permalink,
      "permalink" => permalink
    }
    self.data["redirect_from"] = redirects.uniq unless redirects.empty?
    process(@name)
  end

end

class PodcastEpisodePagesGenerator < Jekyll::Generator
  safe true
  priority :low

  def generate(site)
    feed_data = site.data["latest_podcast_episodes"]
    return unless feed_data.is_a?(Hash)

    episodes_by_feed = feed_data["episodes_by_feed"]
    return unless episodes_by_feed.is_a?(Hash)

    posts = site.posts.respond_to?(:docs) ? site.posts.docs : []
    feed_to_podcast = {}

    posts.each do |doc|
      next unless doc.data["category"] == "podcast"

      feed_url = doc.data["rss_feed"].to_s.strip
      next if feed_url.empty?

      slug = doc.data["slug"].to_s.strip
      next if slug.empty?

      feed_to_podcast[LatestPodcastEpisodes.normalize_feed_key(feed_url)] = doc
    end

    page_count = 0

    episodes_by_feed.each do |feed_key, episodes|
      podcast_doc = feed_to_podcast[feed_key]
      next unless podcast_doc

      podcast_slug = podcast_doc.data["slug"].to_s
      with_slugs = LatestPodcastEpisodes.assign_episode_slugs!(
        Array(episodes).select { |e| e.is_a?(Hash) },
        podcast_slug: podcast_slug
      )

      with_slugs.each do |raw_episode|
        audio = raw_episode["audio_url"].to_s.strip
        title = raw_episode["episode_title"].to_s.strip
        next if audio.empty? || title.empty?

        episode = raw_episode.dup
        episode_slug = episode["episode_slug"].to_s.strip
        next if episode_slug.empty?

        episode["description_html"] = LatestPodcastEpisodes.sanitize_episode_description_html(
          episode["description_html"]
        )
        episode["description_plain"] =
          if episode["description_html"].to_s.strip.empty?
            ""
          else
            LatestPodcastEpisodes.description_plain_from_html(episode["description_html"])
          end

        site.pages << PodcastEpisodePage.new(site, site.source, podcast_doc, episode, episode_slug)
        page_count += 1
      end
    end

    Jekyll.logger.info "PodcastEpisodePages:", "Generated #{page_count} episode page(s)."
  end
end
