# frozen_string_literal: true

# Generates a static page per RSS episode under /{podcast-slug}/{episode-title-slug}/
# using episodes_by_feed from LatestPodcastEpisodes (production RSS or committed YAML).
#
# Incremental mode (default in production): skips episode pages whose on-disk HTML
# matches the stored page_build_fingerprint. Set REBUILD_ALL_EPISODE_PAGES=1 to force.

module PodcastEpisodeRedirects
  module_function

  def paths_for(podcast_slug, episode, episode_slug)
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

    legacy_unicode = episode["legacy_unicode_slug"].to_s.strip
    if legacy_unicode != "" && legacy_unicode != episode_slug
      redirects << "/#{podcast_slug}/#{legacy_unicode}/"
      redirects << "/#{podcast_slug}/#{legacy_unicode}.html"
    end

    redirects.uniq
  end

  def split_redirect_path(path)
    clean = path.to_s.strip.sub(%r{\A/}, "")
    if clean.end_with?(".html")
      parts = clean.split("/")
      dir = parts[0..-2].join("/")
      name = parts[-1]
      [dir, name]
    else
      [clean.sub(%r{/+\z}, ""), "index.html"]
    end
  end

  def absolute_target(site, permalink)
    base = site.config["url"].to_s.chomp("/")
    path = permalink.to_s.start_with?("/") ? permalink : "/#{permalink}"
    "#{base}#{path}"
  end
end

class PodcastEpisodeRedirectPage < Jekyll::Page
  def initialize(site, base, from_path, target_url)
    @site = site
    @base = base
    @dir, @name = PodcastEpisodeRedirects.split_redirect_path(from_path)

    self.content = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
        <meta charset="utf-8">
        <title>Redirecting&hellip;</title>
        <link rel="canonical" href="#{target_url}">
        <script>location="#{target_url}"</script>
        <meta http-equiv="refresh" content="0; url=#{target_url}">
        <meta name="robots" content="noindex">
        <h1>Redirecting&hellip;</h1>
        <a href="#{target_url}">Click here if you are not redirected.</a>
      </html>
    HTML
    self.data = { "sitemap" => false }
    process(@name)
  end
end

class PodcastEpisodePage < Jekyll::Page
  def initialize(site, base, podcast_doc, episode, episode_slug)
    @site = site
    @base = base
    podcast_slug = podcast_doc.data["slug"].to_s
    @dir = podcast_slug
    @name = "#{episode_slug}.html"

    permalink = LatestPodcastEpisodes.episode_page_path(podcast_slug, episode_slug)

    @redirect_paths =
      PodcastEpisodeRedirects.paths_for(podcast_slug, episode, episode_slug)

    description_html = episode["description_html"].to_s
    description_plain = episode["description_plain"].to_s

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
      "spotify_link" => podcast_doc.data["spotify_link"].to_s.strip,
      "apple_podcast_link" => podcast_doc.data["apple_podcast_link"].to_s.strip,
      "tags" => podcast_doc.data["tags"],
      "language" => podcast_doc.data["language"],
      "date" => episode["published_at"],
      "episode_page_url" => permalink,
      "permalink" => permalink,
      "youtube_video_id" => episode["youtube_video_id"].to_s.strip
    }
    if episode["youtube_video_id"].to_s.strip != ""
      episode.delete("page_build_fingerprint")
    end
    process(@name)
  end

  attr_reader :redirect_paths
end

class PodcastEpisodeArchivePage < Jekyll::Page
  def initialize(site, base, podcast_doc, episodes)
    @site = site
    @base = base
    podcast_slug = podcast_doc.data["slug"].to_s
    @dir = File.join(podcast_slug, "episodes")
    @name = "index.html"

    podcast_title = podcast_doc.data["title"].to_s.strip
    seo_show_name = podcast_title
    seo_show_name = "#{seo_show_name} Podcast" unless seo_show_name.downcase.include?("podcast")
    latest_published = episodes.first&.dig("published_at").to_s.strip

    self.data = {
      "layout" => "podcast-episode-archive",
      "category" => "podcast_episode_archive",
      "sitemap" => podcast_doc.data["not_running_related"] != true,
      "title" => "#{seo_show_name} episodes",
      "seo_description" => "Browse all indexed episodes of #{seo_show_name}. Listen in your browser on Best Running Podcasts.",
      "podcast_title" => podcast_doc.data["title"],
      "podcast_url" => podcast_doc.url,
      "podcast_slug" => podcast_slug,
      "cover_image" => podcast_doc.data["cover_image"],
      "rss_feed" => podcast_doc.data["rss_feed"],
      "tags" => podcast_doc.data["tags"],
      "language" => podcast_doc.data["language"],
      "episodes" => episodes,
      "date" => latest_published.empty? ? nil : latest_published,
      "permalink" => "/#{podcast_slug}/episodes/"
    }
    process(@name)
  end
end

class PodcastEpisodePagesGenerator < Jekyll::Generator
  safe true
  priority :low

  def generate_episode_pages?
    return false if ENV["SKIP_EPISODE_PAGES"].to_s == "1"
    return true if ENV["GENERATE_EPISODE_PAGES"].to_s == "1"

    Jekyll.env == "production"
  end

  def prepare_episode(raw_episode)
    episode = raw_episode.dup
    html = episode["description_html"].to_s.strip
    if LatestPodcastEpisodes.skip_data_resanitize? && !html.empty?
      plain = episode["description_plain"].to_s.strip
      episode["description_plain"] =
        if plain.empty?
          LatestPodcastEpisodes.description_plain_from_html(html)
        else
          plain
        end
      return episode
    end

    episode["description_html"] = LatestPodcastEpisodes.sanitize_episode_description_html(
      episode["description_html"]
    )
    episode["description_plain"] =
      if episode["description_html"].to_s.strip.empty?
        ""
      else
        LatestPodcastEpisodes.description_plain_from_html(episode["description_html"])
      end
    episode
  end

  def skip_archive_page?(site, podcast_doc, prepared_episodes)
    return false unless LatestPodcastEpisodes.incremental_episode_pages?
    return false if prepared_episodes.empty?

    podcast_slug = podcast_doc.data["slug"].to_s
    return false if LatestPodcastEpisodes.dirty_podcast_slugs.include?(podcast_slug)

    dest = LatestPodcastEpisodes.archive_page_existing_path(site, podcast_slug)
    return false unless File.file?(dest)

    prepared_episodes.all? do |episode|
      episode_slug = episode["episode_slug"].to_s.strip
      next true if episode_slug.empty?

      LatestPodcastEpisodes.skip_episode_page?(site, podcast_doc, episode, episode_slug)
    end
  end

  def generate(site)
    enabled = generate_episode_pages?
    site.config["podcast_episode_pages_enabled"] = enabled
    unless enabled
      Jekyll.logger.info(
        "PodcastEpisodePages:",
        "Skipped episode and archive pages for local build. Use GENERATE_EPISODE_PAGES=1 to enable."
      )
      return
    end

    feed_data = site.data["latest_podcast_episodes"]
    return unless feed_data.is_a?(Hash)

    episodes_by_feed = feed_data["episodes_by_feed"]
    return unless episodes_by_feed.is_a?(Hash)

    feed_to_podcast = LatestPodcastEpisodes.feed_to_podcast_map(site)

    page_count = 0
    skipped_count = 0

    episodes_by_feed.each do |feed_key, episodes|
      podcast_doc = feed_to_podcast[feed_key.to_s]
      next unless podcast_doc
      next unless LatestPodcastEpisodes.episode_pages_for_doc?(podcast_doc)

      podcast_slug = podcast_doc.data["slug"].to_s
      with_slugs = LatestPodcastEpisodes.assign_episode_slugs!(
        Array(episodes).select { |e| e.is_a?(Hash) },
        podcast_slug: podcast_slug
      )

      prepared = with_slugs.map { |raw| prepare_episode(raw) }

      unless skip_archive_page?(site, podcast_doc, prepared)
        site.pages << PodcastEpisodeArchivePage.new(site, site.source, podcast_doc, with_slugs) unless with_slugs.empty?
      end

      prepared.each do |episode|
        audio = episode["audio_url"].to_s.strip
        title = episode["episode_title"].to_s.strip
        next if audio.empty? || title.empty?

        episode_slug = episode["episode_slug"].to_s.strip
        next if episode_slug.empty?

        if LatestPodcastEpisodes.skip_episode_page?(site, podcast_doc, episode, episode_slug)
          skipped_count += 1
          next
        end

        page = PodcastEpisodePage.new(site, site.source, podcast_doc, episode, episode_slug)
        site.pages << page
        target = PodcastEpisodeRedirects.absolute_target(site, page.data["permalink"])
        page.redirect_paths.each do |from_path|
          site.pages << PodcastEpisodeRedirectPage.new(site, site.source, from_path, target)
        end
        page_count += 1
      end
    end

    if LatestPodcastEpisodes.incremental_episode_pages?
      Jekyll.logger.info(
        "PodcastEpisodePages:",
        "Generated #{page_count} episode page(s); skipped #{skipped_count} unchanged."
      )
    else
      Jekyll.logger.info "PodcastEpisodePages:", "Generated #{page_count} episode page(s)."
    end

    return unless LatestPodcastEpisodes.episode_pages_build?

    feed_data = site.data["latest_podcast_episodes"]
    episodes_by_feed = feed_data.is_a?(Hash) ? feed_data["episodes_by_feed"] : nil
    return unless episodes_by_feed.is_a?(Hash)

    LatestPodcastEpisodes.stamp_episode_fingerprints!(site, episodes_by_feed)
    LatestPodcastEpisodes.write_committed_data(site, feed_data)
  end
end
