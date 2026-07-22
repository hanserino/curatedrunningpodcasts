# frozen_string_literal: true

# Generates a static page per RSS episode under /{podcast-slug}/{episode-title-slug}/
# using episodes_by_feed from LatestPodcastEpisodes (production RSS or committed YAML).

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
      "spotify_link" => podcast_doc.data["spotify_link"].to_s.strip,
      "apple_podcast_link" => podcast_doc.data["apple_podcast_link"].to_s.strip,
      "tags" => podcast_doc.data["tags"],
      "language" => podcast_doc.data["language"],
      "date" => episode["published_at"],
      "episode_page_url" => permalink,
      "permalink" => permalink,
      "youtube_video_id" => episode["youtube_video_id"].to_s.strip
    }
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

      site.pages << PodcastEpisodeArchivePage.new(site, site.source, podcast_doc, with_slugs) unless with_slugs.empty?

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

        page = PodcastEpisodePage.new(site, site.source, podcast_doc, episode, episode_slug)
        site.pages << page
        target = PodcastEpisodeRedirects.absolute_target(site, page.data["permalink"])
        page.redirect_paths.each do |from_path|
          site.pages << PodcastEpisodeRedirectPage.new(site, site.source, from_path, target)
        end
        page_count += 1
      end
    end

    Jekyll.logger.info "PodcastEpisodePages:", "Generated #{page_count} episode page(s)."
  end
end
