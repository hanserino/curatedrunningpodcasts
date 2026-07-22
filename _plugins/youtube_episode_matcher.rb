# frozen_string_literal: true

# Matches RSS podcast episodes to YouTube uploads for shows with youtube_link.
# Prototype scope: singletrack, pr-project, black-hat-ultra (expand via YOUTUBE_MATCH_ALL=1).

require "rexml/document"
require "yaml"

module YoutubeEpisodeMatcher
  USER_AGENT = LatestPodcastEpisodes::USER_AGENT
  OPEN_TIMEOUT = 6
  READ_TIMEOUT = 12
  DATE_WINDOW_SECONDS = 14 * 24 * 60 * 60
  MIN_TITLE_SCORE = 0.42
  PROTOTYPE_SLUGS = %w[singletrack pr-project black-hat-ultra].freeze
  STOPWORDS = %w[
    the and for with from that this podcast project singletrack episode ep part
    about into your you our their they them were was are has have had will just
  ].freeze
  YOUTUBE_WATCH_RX = %r{
    (?:https?:)?//(?:www\.)?(?:youtube\.com/watch\?(?:[^\s"'<>]*&)?v=|youtu\.be/)
    ([a-zA-Z0-9_-]{11})
  }ix.freeze
  CHANNEL_ID_RX = /channel_id=(UC[\w-]{20,})|"channelId":"(UC[\w-]{20,})"/.freeze
  PLAYLIST_ID_RX = %r{[?&]list=(PL[\w-]{10,})}.freeze
  CHANNEL_PATH_RX = %r{youtube\.com/channel/(UC[\w-]{20,})}i.freeze

  module_function

  def fetch_enabled?
    return false if ENV["YOUTUBE_MATCH"].to_s == "0"

    ENV["YOUTUBE_MATCH"].to_s == "1" || LatestPodcastEpisodes.rss_fetch_enabled?
  end

  def match_all_slugs?
    ENV["YOUTUBE_MATCH_ALL"].to_s == "1"
  end

  def enabled_for_podcast?(doc)
    return false unless doc.data["youtube_link"].to_s.strip != ""

    slug = doc.data["slug"].to_s
    match_all_slugs? || PROTOTYPE_SLUGS.include?(slug)
  end

  def channel_cache_path(site)
    site.in_source_dir(".jekyll-rss-cache", "youtube_channel_ids.yml")
  end

  def read_channel_cache(site)
    path = channel_cache_path(site)
    return {} unless File.file?(path)

    YAML.safe_load(File.read(path), permitted_classes: [Time], aliases: true) || {}
  rescue StandardError
    {}
  end

  def write_channel_cache(site, cache)
    path = channel_cache_path(site)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, cache.to_yaml)
  rescue StandardError => e
    Jekyll.logger.warn "YoutubeEpisodeMatcher:", "Could not write #{path}: #{e.message}"
  end

  def fetch_url(url)
    URI.open(
      url,
      "User-Agent" => USER_AGENT,
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    ).read
  end

  def resolve_feed_url(youtube_link, channel_cache)
    link = youtube_link.to_s.strip
    return nil if link.empty?

    if (playlist_id = link[PLAYLIST_ID_RX, 1])
      return "https://www.youtube.com/feeds/videos.xml?playlist_id=#{playlist_id}"
    end

    channel_id =
      link[CHANNEL_PATH_RX, 1] ||
      channel_cache[link] ||
      resolve_channel_id(link, channel_cache)

    return nil if channel_id.to_s.strip.empty?

    "https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}"
  end

  def resolve_channel_id(youtube_link, channel_cache)
    cached = channel_cache[youtube_link]
    return cached if cached.to_s.strip != ""

    html = fetch_url(youtube_link)
    channel_id = html[CHANNEL_ID_RX, 1] || html[CHANNEL_ID_RX, 2]
    channel_cache[youtube_link] = channel_id if channel_id.to_s.strip != ""
    channel_id
  rescue StandardError => e
    Jekyll.logger.debug "YoutubeEpisodeMatcher:", "Channel resolve failed #{youtube_link}: #{e.class}"
    nil
  end

  def parse_youtube_feed(xml)
    doc = REXML::Document.new(xml)
    entries = []

    doc.elements.each("feed/entry") do |entry|
      video_id = entry.elements["yt:videoId"]&.text.to_s.strip
      next if video_id.empty?

      title = entry.elements["title"]&.text.to_s.strip
      published_raw = entry.elements["published"]&.text.to_s.strip
      published_at =
        begin
          Time.parse(published_raw)
        rescue ArgumentError, TypeError
          nil
        end

      alternate_link =
        entry.elements.to_a("link").find { |node| node.attributes["rel"] == "alternate" }
      href = alternate_link ? alternate_link.attributes["href"].to_s : ""
      is_short = href.include?("/shorts/")

      media_description =
        entry.elements["media:group/media:description"]&.text.to_s.strip

      entries << {
        video_id: video_id,
        title: title,
        published_at: published_at,
        watch_url: href,
        is_short: is_short,
        media_description: media_description
      }
    end

    entries
  rescue REXML::ParseException => e
    Jekyll.logger.warn "YoutubeEpisodeMatcher:", "YouTube feed parse error: #{e.message}"
    []
  end

  def normalize_title(title)
    text = title.to_s.downcase
    text = text.gsub(/&amp;|&/i, " and ")
    text = text.gsub(/[''""]/, "")
    text = text.gsub(/\A(?:#?\s*)?(?:ep\.?|episode)\s*#?\s*\d+\s*[-–—:|]+\s*/i, "")
    text = text.gsub(/\s*\|\s*[^|]+\z/, "")
    text = text.gsub(/[^a-z0-9\s]/, " ")
    text.gsub(/\s+/, " ").strip
  end

  def title_tokens(title)
    normalize_title(title)
      .split(" ")
      .reject { |word| word.length < 3 || STOPWORDS.include?(word) }
  end

  def title_similarity(left, right)
    a = title_tokens(left)
    b = title_tokens(right)
    return 0.0 if a.empty? || b.empty?

    shared = (a & b).size
    shared.to_f / (a | b).size
  end

  def normalized_prefix(text, length = 72)
    normalize_title(text)[0, length]
  end

  def descriptions_align?(episode, video)
    plain = episode["description_plain"].to_s
    yt_desc = video[:media_description].to_s
    return false if plain.length < 30 || yt_desc.length < 30

    a = normalized_prefix(plain, 80)
    b = normalized_prefix(yt_desc, 80)
    return true if a.length >= 40 && b.length >= 40 && (a.start_with?(b[0, 40]) || b.start_with?(a[0, 40]))

    title_similarity(plain, yt_desc) >= 0.55
  end

  def episode_time(episode)
    Time.parse(episode["published_at"].to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def within_date_window?(episode_time, video_time)
    return true unless episode_time && video_time

    (episode_time - video_time).abs <= DATE_WINDOW_SECONDS
  end

  def extract_video_id_from_html(html)
    ids = html.to_s.scan(YOUTUBE_WATCH_RX).flatten
    ids = ids.reject { |id| id.to_s.strip.empty? }.uniq
    return nil if ids.empty?
    return ids.first if ids.size == 1

    episode_link = html.to_s.match(
      %r{<a[^>]+href=["'][^"']*(?:youtube\.com/watch\?[^"']*v=|youtu\.be/)([a-zA-Z0-9_-]{11})[^"']*["'][^>]*>([^<]*)</a>}im
    )
    if episode_link
      label = episode_link[2].to_s.downcase
      return episode_link[1] if label.include?("youtube") || label.include?("youtu")
    end

    nil
  end

  def match_episode_candidates(episode, videos)
    from_html = extract_video_id_from_html(episode["description_html"])
    if from_html.to_s.strip != ""
      return [{ video_id: from_html, score: 1.0 }]
    end

    episode_time = episode_time(episode)
    candidates = []

    videos.each do |video|
      next if video[:is_short]
      next unless within_date_window?(episode_time, video[:published_at])

      score = title_similarity(episode["episode_title"], video[:title])
      score = [score, 0.95].max if descriptions_align?(episode, video)
      next if score < MIN_TITLE_SCORE

      candidates << { video_id: video[:video_id], score: score }
    end

    candidates
  end

  def assign_videos_to_episodes!(episodes, videos)
    pairs = []

    Array(episodes).each do |episode|
      next unless episode.is_a?(Hash)

      match_episode_candidates(episode, videos).each do |candidate|
        pairs << {
          episode: episode,
          video_id: candidate[:video_id],
          score: candidate[:score]
        }
      end
    end

    pairs.sort_by! { |pair| -pair[:score] }

    used_episodes = {}
    used_videos = {}

    pairs.each do |pair|
      episode_key = pair[:episode]["episode_slug"].to_s
      video_id = pair[:video_id].to_s
      next if episode_key.empty? || video_id.empty?
      next if used_episodes[episode_key] || used_videos[video_id]

      pair[:episode]["youtube_video_id"] = video_id
      used_episodes[episode_key] = true
      used_videos[video_id] = true
    end

    Array(episodes).each do |episode|
      next unless episode.is_a?(Hash)

      slug = episode["episode_slug"].to_s
      episode.delete("youtube_video_id") unless used_episodes[slug]
    end

    used_episodes.size
  end

  def enrich_episodes_by_feed!(site, episodes_by_feed, feed_to_podcast)
    return 0 unless episodes_by_feed.is_a?(Hash)

    fetch = fetch_enabled?
    channel_cache = read_channel_cache(site)
    channel_cache_before = channel_cache.dup
    matched_count = 0

    episodes_by_feed.each do |feed_key, episodes|
      podcast_doc = feed_to_podcast[feed_key]
      next unless podcast_doc
      next unless enabled_for_podcast?(podcast_doc)

      youtube_link = podcast_doc.data["youtube_link"].to_s.strip
      feed_url = resolve_feed_url(youtube_link, channel_cache)
      next if feed_url.to_s.strip.empty?

      videos = []
      if fetch
        begin
          xml = fetch_url(feed_url)
          videos = parse_youtube_feed(xml)
        rescue StandardError => e
          Jekyll.logger.warn(
            "YoutubeEpisodeMatcher:",
            "YouTube feed failed for #{podcast_doc.data['title']}: #{e.class}"
          )
        end
      end

      episode_list = Array(episodes).select { |episode| episode.is_a?(Hash) }
      if !fetch
        matched_count += episode_list.count { |episode| episode["youtube_video_id"].to_s.strip != "" }
        next
      end

      if videos.empty?
        episode_list.each { |episode| episode.delete("youtube_video_id") }
        next
      end

      matched_count += assign_videos_to_episodes!(episode_list, videos)
    end

    write_channel_cache(site, channel_cache) if channel_cache != channel_cache_before
    matched_count
  end
end

class YoutubeEpisodeEnrichmentGenerator < Jekyll::Generator
  safe true
  priority :normal

  def generate(site)
    feed_data = site.data["latest_podcast_episodes"]
    return unless feed_data.is_a?(Hash)

    episodes_by_feed = feed_data["episodes_by_feed"]
    return unless episodes_by_feed.is_a?(Hash)

    feed_to_podcast = {}
    posts = site.posts.respond_to?(:docs) ? site.posts.docs : []
    posts.each do |doc|
      next unless doc.data["category"] == "podcast"

      feed_url = doc.data["rss_feed"].to_s.strip
      next if feed_url.empty?

      feed_to_podcast[LatestPodcastEpisodes.normalize_feed_key(feed_url)] = doc
    end

    matched =
      YoutubeEpisodeMatcher.enrich_episodes_by_feed!(site, episodes_by_feed, feed_to_podcast)

    return if matched.zero?
    return unless YoutubeEpisodeMatcher.fetch_enabled?

    LatestPodcastEpisodes.write_committed_data(site, feed_data)
    Jekyll.logger.info "YoutubeEpisodeMatcher:", "Matched #{matched} episode(s) to YouTube videos."
  rescue StandardError => e
    Jekyll.logger.warn "YoutubeEpisodeMatcher:", "#{e.class}: #{e.message}"
  end
end
