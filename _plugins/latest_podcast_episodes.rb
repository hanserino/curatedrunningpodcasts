# frozen_string_literal: true

# RSS feeds are fetched only when JEKYLL_ENV=production or JEKYLL_FETCH_RSS=1.
# Otherwise the build uses _data/latest_podcast_episodes.yml (from git) and/or
# .jekyll-rss-cache/latest_podcast_episodes.yml so jekyll serve stays fast.

require "fileutils"
require "open-uri"
require "rss"
require "time"
require "yaml"

module LatestPodcastEpisodes
  # Several podcast hosts reject generic bot user agents with 403 responses.
  # Use a browser-like agent so feed requests are treated like normal clients.
  USER_AGENT = "Mozilla/5.0 (compatible; BestRunningPodcasts/1.0; +https://bestrunningpodcasts.com)".freeze
  OPEN_TIMEOUT = 6
  READ_TIMEOUT = 10

  module_function

  def parse_time(item)
    raw =
      if item.respond_to?(:pubDate) && item.pubDate
        item.pubDate
      elsif item.respond_to?(:dc_date) && item.dc_date
        item.dc_date
      elsif item.respond_to?(:updated) && item.updated
        item.updated
      end

    return nil if raw.nil?

    return raw if raw.is_a?(Time)

    Time.parse(raw.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def latest_item_from_feed(xml)
    parsed = RSS::Parser.parse(xml, false)
    items = Array(parsed&.items).compact
    return nil if items.empty?

    items.max_by { |item| parse_time(item) || Time.at(0) }
  rescue RSS::Error
    nil
  end

  def feed_image_from_xml(xml)
    parsed = RSS::Parser.parse(xml, false)

    itunes_image =
      if parsed.respond_to?(:itunes_image) && parsed.itunes_image
        parsed.itunes_image
      elsif parsed.respond_to?(:channel) && parsed.channel.respond_to?(:itunes_image)
        parsed.channel.itunes_image
      end

    href = itunes_image.respond_to?(:href) ? itunes_image.href.to_s.strip : ""
    return href unless href == ""

    channel_image_url =
      if parsed.respond_to?(:channel) && parsed.channel.respond_to?(:image) && parsed.channel.image
        parsed.channel.image.url.to_s.strip
      else
        ""
      end

    channel_image_url
  rescue RSS::Error
    ""
  end

  def fetch_feed(url)
    URI.open(
      url,
      "User-Agent" => USER_AGENT,
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    ).read
  end

  def normalize_feed_key(url)
    url.to_s.strip.downcase
  end

  # Liquid cannot reliably resolve hash[variable_key] on nested site.data hashes, so we also
  # expose an array of { "feed_key", "episodes" } for the `where` filter in templates.
  def ensure_feed_episodes_list!(h)
    return unless h.is_a?(Hash)

    eb = h["episodes_by_feed"]
    return unless eb.is_a?(Hash)

    h["feed_episodes_list"] = eb.map { |k, eps| { "feed_key" => k.to_s, "episodes" => eps } }
  end

  def episodes_from_feed(xml, limit = 15)
    parsed = RSS::Parser.parse(xml, false)
    items = Array(parsed&.items).compact
    return [] if items.empty?

    items
      .map do |item|
        enclosure_url = item.respond_to?(:enclosure) ? item.enclosure&.url.to_s.strip : ""
        next if enclosure_url == ""

        published_at = parse_time(item) || Time.at(0)
        {
          "episode_title" => item.title.to_s.strip,
          "episode_url" => item.link.to_s.strip,
          "audio_url" => enclosure_url,
          "published_at" => published_at.iso8601
        }
      end
      .compact
      .sort_by { |entry| Time.parse(entry["published_at"].to_s) rescue Time.at(0) }
      .reverse
      .first(limit)
  rescue RSS::Error
    []
  end

  def rss_cache_path(site)
    site.in_source_dir(".jekyll-rss-cache", "latest_podcast_episodes.yml")
  end

  def committed_data_path(site)
    site.in_source_dir("_data", "latest_podcast_episodes.yml")
  end

  def write_committed_data(site, payload)
    return unless ENV["JEKYLL_ENV"].to_s == "production"

    path = committed_data_path(site)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(payload))
  rescue StandardError => e
    Jekyll.logger.warn "LatestPodcastEpisodes:", "Could not write #{path}: #{e.message}"
  end

  def read_rss_cache(path)
    return nil unless File.file?(path)

    # Local cache written by this plugin only (under .jekyll-rss-cache/).
    YAML.load(File.read(path))
  rescue Psych::Exception, ArgumentError, TypeError => e
    Jekyll.logger.warn "LatestPodcastEpisodes:", "Could not read #{path}: #{e.message}"
    nil
  end

  def write_rss_cache(path, payload)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(payload))
  rescue StandardError => e
    Jekyll.logger.warn "LatestPodcastEpisodes:", "Could not write #{path}: #{e.message}"
  end

  def rss_fetch_enabled?
    return true if ENV["JEKYLL_FETCH_RSS"].to_s == "1"

    ENV["JEKYLL_ENV"].to_s == "production"
  end
end

def build_latest_podcast_episodes_data(site)
  cache_path = LatestPodcastEpisodes.rss_cache_path(site)
  cached = LatestPodcastEpisodes.read_rss_cache(cache_path)

  prior_snapshot = site.data["latest_podcast_episodes"]
  prior_snapshot = nil unless prior_snapshot.is_a?(Hash)
  prior_usable =
    prior_snapshot &&
      prior_snapshot["items"].is_a?(Array) &&
      !prior_snapshot["items"].empty?

  cache_usable = cached.is_a?(Hash) && cached["items"].is_a?(Array) && !cached["items"].empty?

  unless LatestPodcastEpisodes.rss_fetch_enabled?
    merged = nil
    source = nil
    if cache_usable
      merged = cached.merge(
        "generated_at" => Time.now.utc.iso8601,
        "rss_fetch_skipped" => true
      )
      source = "disk cache (.jekyll-rss-cache/)"
    elsif prior_usable
      merged = prior_snapshot.merge(
        "generated_at" => Time.now.utc.iso8601,
        "rss_fetch_skipped" => true
      )
      source = "committed _data/latest_podcast_episodes.yml"
    end

    if merged
      LatestPodcastEpisodes.ensure_feed_episodes_list!(merged)
      site.data["latest_podcast_episodes"] = merged
      Jekyll.logger.info(
        "LatestPodcastEpisodes:",
        "Skipped RSS network fetch; using #{source}. Fresh feeds: JEKYLL_ENV=production or JEKYLL_FETCH_RSS=1."
      )
      return
    end

    Jekyll.logger.warn(
      "LatestPodcastEpisodes:",
      "No RSS snapshot (missing _data/latest_podcast_episodes.yml and cache); fetching feeds this run."
    )
  end

  posts = site.posts.respond_to?(:docs) ? site.posts.docs : []

  podcasts = posts.select do |doc|
    doc.data["category"] == "podcast" && doc.data["rss_feed"].to_s.strip != ""
  end

  items = []
  errors = []
  episodes_by_feed = {}

  podcasts.each do |doc|
    feed_url = doc.data["rss_feed"].to_s.strip
    feed_key = LatestPodcastEpisodes.normalize_feed_key(feed_url)

    begin
      xml = LatestPodcastEpisodes.fetch_feed(feed_url)
      episodes = LatestPodcastEpisodes.episodes_from_feed(xml, 20)
      episodes_by_feed[feed_key] = episodes

      latest_item = LatestPodcastEpisodes.latest_item_from_feed(xml)

      if latest_item.nil?
        errors << { "podcast" => doc.data["title"], "rss_feed" => feed_url, "error" => "No parseable episodes found" }
        next
      end

      enclosure_url = latest_item.respond_to?(:enclosure) ? latest_item.enclosure&.url.to_s.strip : ""
      if enclosure_url == ""
        errors << { "podcast" => doc.data["title"], "rss_feed" => feed_url, "error" => "Latest episode has no enclosure URL" }
        next
      end

      published_at = LatestPodcastEpisodes.parse_time(latest_item) || Time.now
      cover_image = doc.data["cover_image"].to_s.strip
      cover_image = LatestPodcastEpisodes.feed_image_from_xml(xml) if cover_image == ""
      items << {
        "podcast_title" => doc.data["title"],
        "podcast_page_url" => doc.url,
        "cover_image" => cover_image,
        "feed_url" => feed_url,
        "episode_title" => latest_item.title.to_s.strip,
        "episode_url" => latest_item.link.to_s.strip,
        "audio_url" => enclosure_url,
        "published_at" => published_at.iso8601
      }
    rescue StandardError => e
      episodes_by_feed[feed_key] = []
      errors << { "podcast" => doc.data["title"], "rss_feed" => feed_url, "error" => "#{e.class}: #{e.message}" }
      Jekyll.logger.debug "LatestPodcastEpisodes:", "Feed failed #{feed_url}: #{e.class} #{e.message}"
    end
  end

  sorted = items.sort_by do |item|
    begin
      Time.parse(item["published_at"].to_s)
    rescue ArgumentError, TypeError
      Time.at(0)
    end
  end.reverse

  payload = {
    "generated_at" => Time.now.utc.iso8601,
    "items" => sorted,
    "episodes_by_feed" => episodes_by_feed,
    "errors" => errors
  }
  LatestPodcastEpisodes.ensure_feed_episodes_list!(payload)

  if sorted.any?
    site.data["latest_podcast_episodes"] = payload
    LatestPodcastEpisodes.write_rss_cache(cache_path, payload)
    LatestPodcastEpisodes.write_committed_data(site, payload)
  elsif podcasts.any? && sorted.empty? && cached.is_a?(Hash) && cached["items"].is_a?(Array) && !cached["items"].empty?
    Jekyll.logger.warn(
      "LatestPodcastEpisodes:",
      "RSS fetch returned no episodes (#{errors.size} problem(s)); using disk cache from #{cached['generated_at']}."
    )
    merged = cached.merge(
      "generated_at" => Time.now.utc.iso8601,
      "cache_fallback" => true,
      "fetch_errors" => errors,
      "items" => cached["items"],
      "episodes_by_feed" => cached["episodes_by_feed"] || {},
      "errors" => cached["errors"] || []
    )
    LatestPodcastEpisodes.ensure_feed_episodes_list!(merged)
    site.data["latest_podcast_episodes"] = merged
  elsif podcasts.any? && sorted.empty? && prior_usable
    Jekyll.logger.warn(
      "LatestPodcastEpisodes:",
      "RSS fetch returned no episodes (#{errors.size} problem(s)); using committed _data/latest_podcast_episodes.yml."
    )
    kept = prior_snapshot.merge(
      "generated_at" => Time.now.utc.iso8601,
      "committed_fallback" => true,
      "fetch_errors" => errors
    )
    LatestPodcastEpisodes.ensure_feed_episodes_list!(kept)
    site.data["latest_podcast_episodes"] = kept
  else
    site.data["latest_podcast_episodes"] = payload
  end
end

class LatestPodcastEpisodesGenerator < Jekyll::Generator
  safe true
  priority :highest

  def generate(site)
    build_latest_podcast_episodes_data(site)
  rescue StandardError => e
    Jekyll.logger.error "LatestPodcastEpisodes:", "#{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}"
    cache_path = LatestPodcastEpisodes.rss_cache_path(site)
    cached = LatestPodcastEpisodes.read_rss_cache(cache_path)
    if cached.is_a?(Hash) && cached["items"].is_a?(Array) && !cached["items"].empty?
      Jekyll.logger.warn "LatestPodcastEpisodes:", "Using disk cache after build error (#{e.class})."
      merged = cached.merge(
        "generated_at" => Time.now.utc.iso8601,
        "cache_fallback" => true,
        "load_error" => "#{e.class}: #{e.message}"
      )
      LatestPodcastEpisodes.ensure_feed_episodes_list!(merged)
      site.data["latest_podcast_episodes"] = merged
      return
    end

    committed_path = LatestPodcastEpisodes.committed_data_path(site)
    committed = LatestPodcastEpisodes.read_rss_cache(committed_path)
    return unless committed.is_a?(Hash) && committed["items"].is_a?(Array) && !committed["items"].empty?

    Jekyll.logger.warn "LatestPodcastEpisodes:", "Using _data/latest_podcast_episodes.yml after build error (#{e.class})."
    merged = committed.merge(
      "generated_at" => Time.now.utc.iso8601,
      "committed_fallback" => true,
      "load_error" => "#{e.class}: #{e.message}"
    )
    LatestPodcastEpisodes.ensure_feed_episodes_list!(merged)
    site.data["latest_podcast_episodes"] = merged
  end
end
