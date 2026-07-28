# frozen_string_literal: true

# Matches RSS podcast episodes to YouTube uploads for shows with youtube_link.

require "fileutils"
require "open-uri"
require "rexml/document"
require "yaml"

module YoutubeEpisodeMatcher
  # YouTube serves 404 HTML to non-browser clients on feeds/videos.xml; use a normal browser UA.
  YOUTUBE_USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36".freeze
  OPEN_TIMEOUT = 6
  READ_TIMEOUT = 12
  DATE_WINDOW_SECONDS = 14 * 24 * 60 * 60
  MIN_TITLE_SCORE = 0.42
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
  EPISODE_NUMBER_RX = /\A(?:#?\s*)?(?:ep\.?|episode)\s*#?\s*(\d+)\b/i.freeze

  module_function

  def fetch_enabled?
    return false if ENV["YOUTUBE_MATCH"].to_s == "0"
    return true if ENV["YOUTUBE_MATCH"].to_s == "1"
    return true if LatestPodcastEpisodes.episode_pages_build?

    LatestPodcastEpisodes.rss_fetch_enabled?
  end

  def enabled_for_podcast?(doc)
    doc.data["youtube_link"].to_s.strip != ""
  end

  def channel_cache_path(site)
    site.in_source_dir(".jekyll-rss-cache", "youtube_channel_ids.yml")
  end

  def committed_channel_cache_path(site)
    site.in_source_dir("_data", "youtube_channel_ids.yml")
  end

  def read_channel_cache(site)
    merged = {}
    [committed_channel_cache_path(site), channel_cache_path(site)].each do |path|
      next unless File.file?(path)

      data = YAML.safe_load(File.read(path), permitted_classes: [Time], aliases: true) || {}
      merged.merge!(data) if data.is_a?(Hash)
    end
    merged
  rescue StandardError
    {}
  end

  def write_channel_cache(site, cache)
    path = channel_cache_path(site)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, cache.to_yaml)

    return unless ENV["JEKYLL_ENV"].to_s == "production"

    committed_path = committed_channel_cache_path(site)
    prior = File.file?(committed_path) ? (YAML.safe_load(File.read(committed_path), aliases: true) || {}) : {}
    prior = {} unless prior.is_a?(Hash)
    combined = prior.merge(cache)
    return if combined == prior

    File.write(committed_path, combined.to_yaml)
  rescue StandardError => e
    Jekyll.logger.warn "YoutubeEpisodeMatcher:", "Could not write channel cache: #{e.message}"
  end

  def fetch_youtube_body(url)
    URI.open(
      url,
      "User-Agent" => YOUTUBE_USER_AGENT,
      "Accept" => "application/atom+xml,application/xml,text/xml,*/*;q=0.8",
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    ).read
  end

  def youtube_feed_xml?(body)
    text = body.to_s.lstrip
    text.start_with?("<?xml", "<feed") && text.include?("<entry")
  end

  def feed_urls_for_channel(channel_id)
    id = channel_id.to_s.strip
    return [] if id.empty?

    urls = ["https://www.youtube.com/feeds/videos.xml?channel_id=#{id}"]
    urls << "https://www.youtube.com/feeds/videos.xml?playlist_id=UU#{id[2..]}" if id.start_with?("UC") && id.length > 2
    urls
  end

  def feed_urls_for_youtube_link(youtube_link, channel_cache)
    link = youtube_link.to_s.strip
    return [] if link.empty?

    urls = []
    if (playlist_id = link[PLAYLIST_ID_RX, 1])
      urls << "https://www.youtube.com/feeds/videos.xml?playlist_id=#{playlist_id}"
    end

    channel_id =
      link[CHANNEL_PATH_RX, 1] ||
      channel_cache[link] ||
      resolve_channel_id(link, channel_cache)

    urls.concat(feed_urls_for_channel(channel_id)) if channel_id.to_s.strip != ""
    urls.uniq
  end

  def fetch_videos_for_youtube_link(youtube_link, channel_cache)
    urls = feed_urls_for_youtube_link(youtube_link, channel_cache)
    return [] if urls.empty?

    last_error = nil
    urls.each do |url|
      body = fetch_youtube_body(url)
      unless youtube_feed_xml?(body)
        raise "Non-feed response from #{url}"
      end

      videos = parse_youtube_feed(body)
      return videos if videos.any?
    rescue StandardError => e
      last_error = e
      Jekyll.logger.debug "YoutubeEpisodeMatcher:", "Feed try failed #{url}: #{e.class}"
    end

    Jekyll.logger.warn(
      "YoutubeEpisodeMatcher:",
      "No YouTube videos parsed for #{youtube_link} (#{urls.size} feed URL(s) tried#{last_error ? ": #{last_error.class}" : ""})."
    )
    []
  end

  def resolve_channel_id(youtube_link, channel_cache)
    cached = channel_cache[youtube_link]
    return cached if cached.to_s.strip != ""

    html = fetch_youtube_body(youtube_link)
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

  def normalize_title(title, podcast_title: nil)
    text = title.to_s.downcase
    text = text.gsub(/&amp;|&/i, " and ")
    text = text.gsub(/[''""]/, "")
    text = text.gsub(/\A(?:#?\s*)?(?:ep\.?|episode)\s*#?\s*\d+\s*[-–—:|]+\s*/i, "")

    parts =
      text.split("|").map do |part|
        part.gsub(/[^a-z0-9\s]/, " ").gsub(/\s+/, " ").strip
      end.reject(&:empty?)

    if podcast_title.to_s.strip != "" && parts.size > 1
      show_key = normalize_show_key(podcast_title)
      last_key = parts.last.gsub(/\bpodcast\b/, " ").gsub(/\s+/, " ").strip
      parts.pop if show_key != "" && (last_key.include?(show_key) || show_key.include?(last_key))
    end

    parts.join(" ").gsub(/\s+/, " ").strip
  end

  def normalize_show_key(text)
    text.to_s.downcase
      .gsub(/&amp;|&/i, " and ")
      .gsub(/[''""]/, "")
      .gsub(/\bpodcast\b/, " ")
      .gsub(/[^a-z0-9\s]/, " ")
      .gsub(/\s+/, " ")
      .strip
  end

  def title_tokens(title, podcast_title: nil)
    normalize_title(title, podcast_title: podcast_title)
      .split(" ")
      .reject { |word| word.length < 3 || STOPWORDS.include?(word) }
  end

  def title_similarity(left, right, podcast_title: nil)
    a = title_tokens(left, podcast_title: podcast_title)
    b = title_tokens(right, podcast_title: podcast_title)
    return 0.0 if a.empty? || b.empty?

    shared = (a & b).size
    shared.to_f / (a | b).size
  end

  def normalized_prefix(text, length = 72, podcast_title: nil)
    normalize_title(text, podcast_title: podcast_title)[0, length]
  end

  def descriptions_align?(episode, video, podcast_title: nil)
    plain = episode["description_plain"].to_s
    yt_desc = video[:media_description].to_s
    return false if plain.length < 30 || yt_desc.length < 30

    a = normalized_prefix(plain, 80, podcast_title: podcast_title)
    b = normalized_prefix(yt_desc, 80, podcast_title: podcast_title)
    return true if a.length >= 40 && b.length >= 40 && (a.start_with?(b[0, 40]) || b.start_with?(a[0, 40]))

    title_similarity(plain, yt_desc, podcast_title: podcast_title) >= 0.55
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

  def episode_number(title)
    match = title.to_s.match(EPISODE_NUMBER_RX)
    match ? match[1].to_i : nil
  end

  def episode_numbers_compatible?(episode_title, video_title)
    episode_num = episode_number(episode_title)
    video_num = episode_number(video_title)
    return true unless episode_num && episode_num.positive?
    return true unless video_num && video_num.positive?

    episode_num == video_num
  end

  def shared_show_notes_video_ids(episodes)
    counts = Hash.new(0)

    Array(episodes).each do |episode|
      next unless episode.is_a?(Hash)

      video_id = extract_video_id_from_html(episode["description_html"])
      counts[video_id] += 1 if video_id.to_s.strip != ""
    end

    counts.select { |_video_id, count| count > 1 }.keys
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

  def html_video_id_trusted?(video_id, videos)
    return false if video_id.to_s.strip.empty?

    # When we have the channel feed, only trust show-notes links that appear on it.
    return videos.any? { |video| video[:video_id] == video_id } unless videos.empty?

    true
  end

  def match_episode_candidates(episode, videos, podcast_title: nil, shared_html_video_ids: [])
    from_html = extract_video_id_from_html(episode["description_html"])
    if html_video_id_trusted?(from_html, videos) && !shared_html_video_ids.include?(from_html)
      return [{ video_id: from_html, score: 1.0 }]
    end

    episode_time = episode_time(episode)
    candidates = []

    videos.each do |video|
      next if video[:is_short]
      next unless episode_numbers_compatible?(episode["episode_title"], video[:title])
      next unless within_date_window?(episode_time, video[:published_at])

      score = title_similarity(episode["episode_title"], video[:title], podcast_title: podcast_title)
      score = [score, 0.95].max if descriptions_align?(episode, video, podcast_title: podcast_title)
      next if score < MIN_TITLE_SCORE

      candidates << { video_id: video[:video_id], score: score }
    end

    candidates
  end

  def assign_videos_to_episodes!(episodes, videos, podcast_title: nil)
    pairs = []
    shared_html_video_ids = shared_show_notes_video_ids(episodes)

    Array(episodes).each do |episode|
      next unless episode.is_a?(Hash)

      match_episode_candidates(
        episode,
        videos,
        podcast_title: podcast_title,
        shared_html_video_ids: shared_html_video_ids
      ).each do |candidate|
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
      pair[:episode].delete("page_build_fingerprint")
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
      podcast_doc = feed_to_podcast[feed_key.to_s]
      next unless podcast_doc
      next unless enabled_for_podcast?(podcast_doc)

      youtube_link = podcast_doc.data["youtube_link"].to_s.strip
      next if youtube_link.empty?

      videos = []
      fetch_failed = false
      if fetch
        begin
          videos = fetch_videos_for_youtube_link(youtube_link, channel_cache)
        rescue StandardError => e
          fetch_failed = true
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
        next if fetch_failed

        episode_list.each { |episode| episode.delete("youtube_video_id") }
        next
      end

      matched_count += assign_videos_to_episodes!(
        episode_list,
        videos,
        podcast_title: podcast_doc.data["title"]
      )
    end

    write_channel_cache(site, channel_cache) if channel_cache != channel_cache_before
    matched_count
  end

  def enrich_site!(site)
    return 0 unless fetch_enabled?

    feed_data = site.data["latest_podcast_episodes"]
    return 0 unless feed_data.is_a?(Hash)

    episodes_by_feed = feed_data["episodes_by_feed"]
    return 0 unless episodes_by_feed.is_a?(Hash)

    feed_to_podcast = LatestPodcastEpisodes.feed_to_podcast_map(site)
    matched = enrich_episodes_by_feed!(site, episodes_by_feed, feed_to_podcast)

    if matched.positive?
      LatestPodcastEpisodes.write_committed_data(site, feed_data)
      Jekyll.logger.info "YoutubeEpisodeMatcher:", "Matched #{matched} episode(s) to YouTube videos."
    else
      Jekyll.logger.info "YoutubeEpisodeMatcher:", "YouTube matching finished with 0 new assignments."
    end

    matched
  end
end
