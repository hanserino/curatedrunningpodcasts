# frozen_string_literal: true

require "timeout"

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
    duration_seconds = episode["duration_seconds"]
    self.data["duration_seconds"] = duration_seconds unless duration_seconds.nil?
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

  SANITIZE_TIMEOUT_SECONDS = 45

  def prepare_episode(raw_episode)
    episode = raw_episode.dup
    html = episode["description_html"].to_s.strip
    return episode if html.empty?

    # Episode-pages CI reads committed _data without bulk resanitize; always run the
    # sanitizer here so HTML/plugin improvements apply to existing show notes.
    slug = episode["episode_slug"].to_s.strip
    begin
      Timeout.timeout(SANITIZE_TIMEOUT_SECONDS) do
        episode["description_html"] = LatestPodcastEpisodes.sanitize_episode_description_html(html)
      end
    rescue Timeout::Error
      Jekyll.logger.warn(
        "PodcastEpisodePages:",
        "Show-note sanitize timed out after #{SANITIZE_TIMEOUT_SECONDS}s for #{slug} (#{html.length} chars); using plain-text fallback."
      )
      episode["description_html"] =
        LatestPodcastEpisodes.sanitize_episode_description_html_fallback(html)
    end
    episode["description_plain"] =
      LatestPodcastEpisodes.description_plain_from_html(episode["description_html"])
    episode
  end

  def skip_archive_page?(site, podcast_doc, episodes)
    return false unless LatestPodcastEpisodes.incremental_episode_pages?
    return false if episodes.empty?

    podcast_slug = podcast_doc.data["slug"].to_s
    return false if LatestPodcastEpisodes.dirty_podcast_slugs.include?(podcast_slug)

    dest = LatestPodcastEpisodes.archive_page_existing_path(site, podcast_slug)
    return false unless File.file?(dest)

    episodes.all? do |episode|
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
    deferred_count = 0
    max_new = LatestPodcastEpisodes.max_new_episode_pages_per_build
    pending = []
    incremental = LatestPodcastEpisodes.incremental_episode_pages?
    rebuild_all = ENV["REBUILD_ALL_EPISODE_PAGES"].to_s == "1"
    Jekyll.logger.info(
      "PodcastEpisodePages:",
      "Scanning #{episodes_by_feed.size} feed(s) (incremental=#{incremental}, rebuild_all=#{rebuild_all}, max_new=#{max_new || 'unlimited'})."
    )

    episodes_by_feed.each do |feed_key, episodes|
      podcast_doc = feed_to_podcast[feed_key.to_s]
      next unless podcast_doc
      next unless LatestPodcastEpisodes.episode_pages_for_doc?(podcast_doc)

      podcast_slug = podcast_doc.data["slug"].to_s
      with_slugs = LatestPodcastEpisodes.assign_episode_slugs!(
        Array(episodes).select { |e| e.is_a?(Hash) },
        podcast_slug: podcast_slug
      )

      unless skip_archive_page?(site, podcast_doc, with_slugs)
        site.pages << PodcastEpisodeArchivePage.new(site, site.source, podcast_doc, with_slugs) unless with_slugs.empty?
      end

      with_slugs.each do |raw|
        audio = raw["audio_url"].to_s.strip
        title = raw["episode_title"].to_s.strip
        next if audio.empty? || title.empty?

        episode_slug = raw["episode_slug"].to_s.strip
        next if episode_slug.empty?

        if LatestPodcastEpisodes.skip_episode_page?(site, podcast_doc, raw, episode_slug)
          skipped_count += 1
          next
        end

        published_at =
          begin
            Time.parse(raw["published_at"].to_s)
          rescue ArgumentError, TypeError
            Time.at(0)
          end

        pending << {
          podcast_doc: podcast_doc,
          raw: raw,
          episode_slug: episode_slug,
          published_at: published_at
        }
      end
    end

    # Newest first so EPISODE_PAGES_MAX_NEW never defers today's episodes behind
    # an older backlog when fingerprints are dirty or a prior run timed out.
    pending.sort_by! { |row| row[:published_at] }.reverse!

    Jekyll.logger.info(
      "PodcastEpisodePages:",
      "Scan complete: #{pending.size} pending, #{skipped_count} skipped unchanged."
    )

    pending.each do |row|
      if max_new && page_count >= max_new
        deferred_count += 1
        next
      end

      if page_count.positive? && (page_count % 25).zero?
        Jekyll.logger.info(
          "PodcastEpisodePages:",
          "Prepared #{page_count} episode page(s) so far…"
        )
      end

      Jekyll.logger.info(
        "PodcastEpisodePages:",
        "Preparing #{row[:episode_slug]} (#{page_count + 1}/#{max_new || pending.size})…"
      )

      episode = prepare_episode(row[:raw])
      page = PodcastEpisodePage.new(
        site,
        site.source,
        row[:podcast_doc],
        episode,
        row[:episode_slug]
      )
      site.pages << page
      target = PodcastEpisodeRedirects.absolute_target(site, page.data["permalink"])
      page.redirect_paths.each do |from_path|
        site.pages << PodcastEpisodeRedirectPage.new(site, site.source, from_path, target)
      end
      page_count += 1
    end

    if LatestPodcastEpisodes.incremental_episode_pages?
      msg = "Generated #{page_count} episode page(s); skipped #{skipped_count} unchanged."
      msg += " Deferred #{deferred_count} (EPISODE_PAGES_MAX_NEW=#{max_new})." if deferred_count.positive?
      Jekyll.logger.info("PodcastEpisodePages:", msg)
    else
      msg = "Generated #{page_count} episode page(s)."
      msg += " Deferred #{deferred_count} (EPISODE_PAGES_MAX_NEW=#{max_new})." if deferred_count.positive?
      Jekyll.logger.info "PodcastEpisodePages:", msg
    end

    return unless LatestPodcastEpisodes.episode_pages_build?

    feed_data = site.data["latest_podcast_episodes"]
    episodes_by_feed = feed_data.is_a?(Hash) ? feed_data["episodes_by_feed"] : nil
    return unless episodes_by_feed.is_a?(Hash)

    LatestPodcastEpisodes.stamp_episode_fingerprints!(site, episodes_by_feed)
    LatestPodcastEpisodes.reconcile_directory_items!(
      feed_data["items"],
      episodes_by_feed
    )
    LatestPodcastEpisodes.write_committed_data(site, feed_data)
  end
end
