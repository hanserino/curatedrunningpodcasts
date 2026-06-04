# frozen_string_literal: true

# RSS feeds are fetched only when JEKYLL_ENV=production or JEKYLL_FETCH_RSS=1.
# Otherwise the build uses _data/latest_podcast_episodes.yml (from git) and/or
# .jekyll-rss-cache/latest_podcast_episodes.yml so jekyll serve stays fast.
#
# All podcasts with rss_feed get episodes_by_feed (for single podcast pages).
# Only running-directory shows (not_running_related != true) appear in items
# (for /latest-episodes/ and the home directory snapshot).

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
  # Non-breaking space as entity, numeric reference, or literal character (feeds often use <p>&nbsp;</p> spacers).
  NBSP_ENTITY_RX = /(?:&nbsp;|&#0*160;|&#x0*a0;|&amp;nbsp;|\u00A0)/i.freeze
  PARAGRAPH_ONLY_NBSP_RX =
    %r{<p(\s[^>]*)?>(?:\s|<br\s*/?>|#{NBSP_ENTITY_RX.source})*</p>}im.freeze

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

  def filter_category_for_doc(doc)
    tags = Array(doc.data["tags"]).map { |t| t.to_s.strip }.reject(&:empty?)
    langs = Array(doc.data["language"]).map { |l| l.to_s.strip }.reject(&:empty?)
    (tags + langs).join(" ").strip
  end

  # Liquid cannot reliably resolve hash[variable_key] on nested site.data hashes, so we also
  # expose an array of { "feed_key", "episodes" } for the `where` filter in templates.
  def ensure_feed_episodes_list!(h)
    return unless h.is_a?(Hash)

    eb = h["episodes_by_feed"]
    return unless eb.is_a?(Hash)

    h["feed_episodes_list"] = eb.map { |k, eps| { "feed_key" => k.to_s, "episodes" => eps } }
  end

  # When a feed fetch fails, keep prior committed or disk-cache episodes for that feed key.
  def merge_episodes_by_feed(fresh, prior, cache)
    return fresh unless fresh.is_a?(Hash)

    fresh.each_with_object({}) do |(key, episodes), merged|
      k = key.to_s
      if episodes.is_a?(Array) && !episodes.empty?
        merged[k] = episodes
        next
      end

      from_prior = prior[k] if prior.is_a?(Hash)
      from_cache = cache[k] if cache.is_a?(Hash)
      fallback =
        if from_prior.is_a?(Array) && !from_prior.empty?
          from_prior
        elsif from_cache.is_a?(Array) && !from_cache.empty?
          from_cache
        end
      merged[k] = fallback || episodes
    end
  end

  def description_plain_from_html(html)
    html.to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
  end

  def strip_nbsp_entities(text)
    text.to_s.gsub(NBSP_ENTITY_RX, " ")
  end

  def html_inner_blank?(inner)
    strip_nbsp_entities(inner)
      .gsub(/<br\s*\/?>/i, " ")
      .gsub(/<[^>]+>/, "")
      .gsub(/\s+/, "")
      .empty?
  end

  def strip_paragraphs_with_only_nbsp(html)
    prev = nil
    cleaned = html.to_s
    while cleaned != prev
      prev = cleaned
      cleaned = cleaned.gsub(PARAGRAPH_ONLY_NBSP_RX, "")
    end
    cleaned
  end

  def strip_empty_block_tags(html)
    cleaned = html.to_s
    %w[p div h1 h2 h3 h4 h5 h6 li].each do |tag|
      loop do
        next_html = cleaned.gsub(
          /<(#{tag})(\s[^>]*)?>(.*?)<\/\1>/im
        ) do
          html_inner_blank?(::Regexp.last_match(3)) ? "" : ::Regexp.last_match(0)
        end
        break if next_html == cleaned

        cleaned = next_html
      end
    end
    cleaned
  end

  def sanitize_episode_description_html(html)
    cleaned = html.to_s.strip
    return "" if cleaned.empty?

    cleaned = cleaned.gsub(/\r\n?/, "\n")
    cleaned = strip_paragraphs_with_only_nbsp(cleaned)
    cleaned = strip_nbsp_entities(cleaned)
    # Podcast show notes often use <br> for line breaks; remove and keep text flowing in blocks.
    cleaned = cleaned.gsub(/<br\s*\/?>/i, " ")

    cleaned = strip_empty_block_tags(cleaned)

    loop do
      next_html = cleaned.gsub(/<p(\s[^>]*)?>\s*<\/p>/i, "")
      break if next_html == cleaned

      cleaned = next_html
    end

    cleaned = cleaned.gsub(/<(p|div|li)(\s[^>]*)?>\s+/, '<\1\2>')
    cleaned = cleaned.gsub(/\s+<\/(p|div|li)>/, "</\\1>")
    cleaned = cleaned.gsub(/>\s+</, "><")
    cleaned.strip
  end

  def episode_image_url(item)
    if item.respond_to?(:itunes_image) && item.itunes_image
      href =
        if item.itunes_image.respond_to?(:href)
          item.itunes_image.href.to_s.strip
        else
          item.itunes_image.to_s.strip
        end
      return href unless href.empty?
    end

    if item.respond_to?(:media_thumbnail) && item.media_thumbnail
      thumb = item.media_thumbnail
      url =
        if thumb.respond_to?(:url) && thumb.url
          thumb.url
        elsif thumb.respond_to?(:content) && thumb.content
          thumb.content
        else
          ""
        end
      url = url.to_s.strip
      return url unless url.empty?
    end

    if item.respond_to?(:image) && item.image
      img = item.image
      url = img.respond_to?(:url) ? img.url.to_s.strip : img.to_s.strip
      return url unless url.empty?
    end

    ""
  end

  def episode_description_html(item)
    candidates = []
    %i[content_encoded itunes_summary description itunes_subtitle dc_description summary].each do |meth|
      next unless item.respond_to?(meth)

      value = item.public_send(meth)
      candidates << value if value
    end

    raw = candidates.map(&:to_s).map(&:strip).find { |text| !text.empty? } || ""
    sanitize_episode_description_html(raw)
  end

  def normalize_audio_key(url)
    url.to_s.strip.downcase.sub(/\?.*\z/, "")
  end

  def episodes_need_feed_backfill?(episodes_by_feed)
    return false unless episodes_by_feed.is_a?(Hash)

    episodes_by_feed.any? do |_, episodes|
      Array(episodes).any? do |entry|
        next false unless entry.is_a?(Hash)

        entry["description_html"].to_s.strip.empty? ||
          entry["episode_image_url"].to_s.strip.empty?
      end
    end
  end

  def backfill_episodes_from_feed!(episodes, xml)
    parsed = RSS::Parser.parse(xml, false)
    lookup = {}

    Array(parsed&.items).each do |item|
      audio = item.respond_to?(:enclosure) ? item.enclosure&.url.to_s.strip : ""
      next if audio.empty?

      lookup[normalize_audio_key(audio)] = item
    end

    Array(episodes).each do |entry|
      next unless entry.is_a?(Hash)

      item = lookup[normalize_audio_key(entry["audio_url"])]
      next unless item

      if entry["description_html"].to_s.strip.empty?
        html = episode_description_html(item)
        unless html.empty?
          entry["description_html"] = html
          entry["description_plain"] = description_plain_from_html(html)
        end
      else
        entry["description_html"] = sanitize_episode_description_html(entry["description_html"])
        entry["description_plain"] = description_plain_from_html(entry["description_html"])
      end

      next unless entry["episode_image_url"].to_s.strip.empty?

      image_url = episode_image_url(item)
      entry["episode_image_url"] = image_url unless image_url.empty?
    end
  end

  def backfill_episodes_from_feeds!(site, podcasts_with_feed, episodes_by_feed)
    return episodes_by_feed unless episodes_by_feed.is_a?(Hash)
    return episodes_by_feed unless episodes_need_feed_backfill?(episodes_by_feed)

    backfilled_feeds = 0
    podcasts_with_feed.each do |doc|
      feed_url = doc.data["rss_feed"].to_s.strip
      next if feed_url.empty?

      feed_key = normalize_feed_key(feed_url)
      episodes = episodes_by_feed[feed_key]
      next unless episodes.is_a?(Array) && !episodes.empty?
      next unless episodes.any? do |entry|
        entry["description_html"].to_s.strip.empty? ||
          entry["episode_image_url"].to_s.strip.empty?
      end

      begin
        xml = fetch_feed(feed_url)
        backfill_episodes_from_feed!(episodes, xml)
        backfilled_feeds += 1
      rescue StandardError => e
        Jekyll.logger.debug "LatestPodcastEpisodes:", "Episode metadata backfill failed #{feed_url}: #{e.class}"
      end
    end

    if backfilled_feeds.positive?
      Jekyll.logger.info(
        "LatestPodcastEpisodes:",
        "Backfilled episode metadata from #{backfilled_feeds} RSS feed(s)."
      )
      cache_path = rss_cache_path(site)
      payload = site.data["latest_podcast_episodes"]
      write_rss_cache(cache_path, payload) if payload.is_a?(Hash)
    end

    episodes_by_feed
  end

  def podcast_posts_with_feed(site)
    posts = site.posts.respond_to?(:docs) ? site.posts.docs : []
    posts.select do |doc|
      doc.data["category"] == "podcast" && doc.data["rss_feed"].to_s.strip != ""
    end
  end

  def slugify_segment(text)
    return "" if text.to_s.strip.empty?

    Jekyll::Utils.slugify(text.to_s, mode: "default")
  end

  def legacy_numbered_episode_slug(index)
    n = index + 1
    width = if n >= 1000
              4
            elsif n >= 100
              3
            else
              2
            end
    format("episode-%0#{width}d", n)
  end

  def episode_uid_from_item(item)
    guid_raw =
      if item.respond_to?(:guid) && item.guid
        item.guid.respond_to?(:content) ? item.guid.content.to_s : item.guid.to_s
      else
        ""
      end
    guid_raw = guid_raw.strip
    guid_raw = guid_raw.split("/").last if guid_raw.include?("://")

    base = slugify_segment(guid_raw)
    return "" if base.empty?

    base[0, 96]
  end

  def episode_slug_for_title(title, published_at: nil, used_slugs: [])
    base = slugify_segment(title.to_s)
    if base.empty? && published_at
      base = slugify_segment(published_at.strftime("%Y-%m-%d"))
    end
    base = "episode" if base.empty?
    base = base[0, 120]

    slug = base
    suffix = 2
    while used_slugs.include?(slug)
      slug = "#{base}-#{suffix}"
      suffix += 1
    end
    used_slugs << slug
    slug
  end

  def episode_page_path(podcast_slug, episode_slug)
    "/#{podcast_slug}/#{episode_slug}/"
  end

  def assign_episode_slugs!(episodes, podcast_slug: nil)
    used_slugs = []
    Array(episodes).each_with_index do |entry, index|
      title = entry["episode_title"].to_s
      published_at =
        begin
          Time.parse(entry["published_at"].to_s)
        rescue ArgumentError, TypeError
          nil
        end
      slug = episode_slug_for_title(title, published_at: published_at, used_slugs: used_slugs)
      entry["episode_slug"] = slug
      entry["episode_key"] = slug
      entry["legacy_numbered_slug"] = legacy_numbered_episode_slug(index)
      next if podcast_slug.to_s.strip.empty?

      entry["episode_page_url"] = episode_page_path(podcast_slug, slug)
    end
    episodes
  end

  def episodes_from_feed(xml, limit = 15, podcast_slug: nil)
    parsed = RSS::Parser.parse(xml, false)
    items = Array(parsed&.items).compact
    return [] if items.empty?

    sorted =
      items
        .map do |item|
          enclosure_url = item.respond_to?(:enclosure) ? item.enclosure&.url.to_s.strip : ""
          next if enclosure_url == ""

          title = item.title.to_s.strip
          next if title.empty?

          published_at = parse_time(item) || Time.at(0)
          description_html = episode_description_html(item)
          image_url = episode_image_url(item)
          {
            "episode_title" => title,
            "episode_url" => item.link.to_s.strip,
            "audio_url" => enclosure_url,
            "published_at" => published_at.iso8601,
            "description_html" => description_html,
            "description_plain" => description_plain_from_html(description_html),
            "episode_image_url" => image_url,
            "episode_uid" => episode_uid_from_item(item)
          }
        end
        .compact
        .sort_by { |entry| Time.parse(entry["published_at"].to_s) rescue Time.at(0) }
        .reverse
        .first(limit)
    assign_episode_slugs!(sorted, podcast_slug: podcast_slug)
  rescue RSS::Error
    []
  end

  def episodes_per_podcast_limit
    Integer(ENV.fetch("EPISODE_PAGES_PER_PODCAST", "25"))
  rescue ArgumentError, TypeError
    25
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
    File.write(path, dump_yaml(payload))
  rescue StandardError => e
    Jekyll.logger.warn "LatestPodcastEpisodes:", "Could not write #{path}: #{e.message}"
  end

  def load_yaml_file(path)
    content = File.read(path)
    YAML.load(content, aliases: true)
  rescue ArgumentError
    YAML.load(content)
  end

  def dump_yaml(payload)
    if YAML.respond_to?(:dump)
      begin
        YAML.dump(payload, line_width: -1, alias: false)
      rescue ArgumentError
        YAML.dump(payload)
      end
    else
      YAML.dump(payload)
    end
  end

  def read_rss_cache(path)
    return nil unless File.file?(path)

    # Local cache written by this plugin only (under .jekyll-rss-cache/).
    load_yaml_file(path)
  rescue Psych::Exception, ArgumentError, TypeError => e
    Jekyll.logger.warn "LatestPodcastEpisodes:", "Could not read #{path}: #{e.message}"
    nil
  end

  def write_rss_cache(path, payload)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, dump_yaml(payload))
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
      podcasts_with_feed = LatestPodcastEpisodes.podcast_posts_with_feed(site)
      if LatestPodcastEpisodes.episodes_need_feed_backfill?(merged["episodes_by_feed"])
        LatestPodcastEpisodes.backfill_episodes_from_feeds!(
          site,
          podcasts_with_feed,
          merged["episodes_by_feed"]
        )
      end
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

  podcasts_with_feed = posts.select do |doc|
    doc.data["category"] == "podcast" &&
      doc.data["rss_feed"].to_s.strip != ""
  end

  items = []
  errors = []
  episodes_by_feed = {}

  podcasts_with_feed.each do |doc|
    feed_url = doc.data["rss_feed"].to_s.strip
    feed_key = LatestPodcastEpisodes.normalize_feed_key(feed_url)
    include_in_directory = doc.data["not_running_related"] != true

    begin
      xml = LatestPodcastEpisodes.fetch_feed(feed_url)
      podcast_slug = doc.data["slug"].to_s.strip
      episode_limit = LatestPodcastEpisodes.episodes_per_podcast_limit
      episodes = LatestPodcastEpisodes.episodes_from_feed(xml, episode_limit, podcast_slug: podcast_slug)
      episodes_by_feed[feed_key] = episodes

      next unless include_in_directory

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
      latest_episode_meta = episodes.is_a?(Array) ? episodes.first : nil
      items << {
        "podcast_title" => doc.data["title"],
        "podcast_page_url" => doc.url,
        "cover_image" => cover_image,
        "feed_url" => feed_url,
        "filter_category" => LatestPodcastEpisodes.filter_category_for_doc(doc),
        "episode_title" => latest_item.title.to_s.strip,
        "episode_url" => latest_item.link.to_s.strip,
        "audio_url" => enclosure_url,
        "published_at" => published_at.iso8601,
        "episode_key" => latest_episode_meta&.dig("episode_slug"),
        "episode_slug" => latest_episode_meta&.dig("episode_slug"),
        "episode_page_url" => latest_episode_meta&.dig("episode_page_url")
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

  feeds_with_episodes = episodes_by_feed.count do |_, episodes|
    episodes.is_a?(Array) && !episodes.empty?
  end
  has_episodes_by_feed = feeds_with_episodes.positive?
  fetch_looks_healthy =
    sorted.any? &&
      (podcasts_with_feed.empty? || feeds_with_episodes >= (podcasts_with_feed.size * 0.5).ceil)

  prior_episodes = prior_snapshot.is_a?(Hash) ? prior_snapshot["episodes_by_feed"] : nil
  cache_episodes = cached.is_a?(Hash) ? cached["episodes_by_feed"] : nil
  episodes_by_feed = LatestPodcastEpisodes.merge_episodes_by_feed(
    episodes_by_feed,
    prior_episodes,
    cache_episodes
  )

  feeds_with_episodes = episodes_by_feed.count do |_, episodes|
    episodes.is_a?(Array) && !episodes.empty?
  end
  has_episodes_by_feed = feeds_with_episodes.positive?

  payload = {
    "generated_at" => Time.now.utc.iso8601,
    "items" => sorted,
    "episodes_by_feed" => episodes_by_feed,
    "errors" => errors
  }
  LatestPodcastEpisodes.ensure_feed_episodes_list!(payload)

  if fetch_looks_healthy
    site.data["latest_podcast_episodes"] = payload
    LatestPodcastEpisodes.write_rss_cache(cache_path, payload)
    LatestPodcastEpisodes.write_committed_data(site, payload)
  elsif podcasts_with_feed.any? && !fetch_looks_healthy && cached.is_a?(Hash) && cached["items"].is_a?(Array) && !cached["items"].empty?
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
  elsif podcasts_with_feed.any? && !fetch_looks_healthy && prior_usable
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
