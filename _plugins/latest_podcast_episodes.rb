# frozen_string_literal: true

# RSS feeds are fetched only when JEKYLL_ENV=production or JEKYLL_FETCH_RSS=1.
# Otherwise the build uses _data/latest_podcast_episodes.yml (from git) and/or
# .jekyll-rss-cache/latest_podcast_episodes.yml so jekyll serve stays fast.
#
# All podcasts with rss_feed get episodes_by_feed (for single podcast pages).
# Only running-directory shows (not_running_related != true) appear in items
# (for /latest-episodes/ and the home directory snapshot).

require "cgi"
require "fileutils"
require "open-uri"
require "rss"
require "time"
require "uri"
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
  HTML_TOKEN_RX = /(<[^>]+>)/i.freeze
  AUTOLINK_URL_RX = %r{
    (?<![\w@/])
    (
      (?:https?://|www\.)[^\s<>"']+
      |
      (?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:[a-z]{2,63})(?:/[^\s<>"']*)?
    )
  }ix.freeze
  SOCIAL_LABEL_HANDLE_RX = /
    \b(Instagram|Twitter|X|TikTok|YouTube)
    \s*:\s*
    (@[A-Za-z0-9_.]{1,30})
  /ix.freeze

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

  def resanitize_episode_descriptions!(episodes_by_feed)
    return unless episodes_by_feed.is_a?(Hash)

    episodes_by_feed.each_value do |episodes|
      Array(episodes).each do |entry|
        next unless entry.is_a?(Hash)

        html = entry["description_html"].to_s.strip
        next if html.empty?

        sanitized = sanitize_episode_description_html(html)
        entry["description_html"] = sanitized
        entry["description_plain"] = description_plain_from_html(sanitized)
      end
    end
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

  def normalize_autolink_href(url)
    href = url.to_s.strip
    if href.match?(/\Awww\./i)
      "https://#{href}"
    elsif href.match?(/\Ahttps?:\/\//i)
      href
    else
      "https://#{href}"
    end
  end

  def strip_trailing_url_punctuation(url)
    trimmed = url.to_s
    trailing = +""
    while trimmed.match?(/[.,;:!?)+\]}]+\z/)
      trailing = trimmed[-1] + trailing
      trimmed = trimmed[0..-2]
    end
    [trimmed, trailing]
  end

  def linkify_bare_urls_in_text(text)
    text.gsub(AUTOLINK_URL_RX) do
      url, trailing = strip_trailing_url_punctuation(Regexp.last_match(1))
      next Regexp.last_match(0) if url.empty?

      href = normalize_autolink_href(url)
      label = CGI.escapeHTML(url)
      %(<a href="#{CGI.escapeHTML(href)}" rel="noopener noreferrer" target="_blank">#{label}</a>) + trailing
    end
  end

  # Buzzsprout (and some other hosts) occasionally wrap only the first letter of a
  # sponsor name in <a>, e.g. <a href="...">N</a>orthcom — merge back into one link.
  SPLIT_WORD_LINK_RX =
    %r{<a\s+([^>]*?)>([A-Za-zÀ-ÖØ-öø-ÿ])</a>([a-zà-öø-ÿ][a-zA-ZÀ-ÖØ-öø-ÿ0-9&'’.\s-]*?)(?=<(?:/li|/p|/a|/ul|/ol|/div|/span|/h[1-6])|[,.;]|$|<)}i.freeze

  def repair_split_word_links(html)
    html.to_s.gsub(SPLIT_WORD_LINK_RX) do
      attrs = Regexp.last_match(1)
      first = Regexp.last_match(2)
      rest = Regexp.last_match(3)
      %(<a #{attrs}>#{first}#{rest}</a>)
    end
  end

  def linkify_bare_urls_in_html(html)
    inside_anchor = false

    html.to_s.split(HTML_TOKEN_RX).map do |part|
      if part.start_with?("<")
        inside_anchor = true if part.match?(/<\s*a[\s>]/i)
        inside_anchor = false if part.match?(/<\s*\/\s*a\s*>/i)
        part
      elsif inside_anchor
        part
      else
        linkify_bare_urls_in_text(part)
      end
    end.join
  end

  def format_inline_external_link(href, label)
    safe_href = CGI.escapeHTML(href.to_s.strip)
    safe_label = CGI.escapeHTML(label.to_s.strip)
    %(<a href="#{safe_href}" rel="noopener noreferrer" target="_blank">#{safe_label}</a>)
  end

  def social_profile_url_for_handle(platform, handle)
    user = handle.to_s.strip.sub(/\A@/, "")
    return "" if user.empty?

    case platform.to_s.strip.downcase
    when "instagram"
      "https://www.instagram.com/#{user}/"
    when "twitter", "x"
      "https://x.com/#{user}"
    when "tiktok"
      "https://www.tiktok.com/@#{user}"
    when "youtube"
      "https://www.youtube.com/@#{user}"
    else
      ""
    end
  end

  def linkify_social_handles_in_text(text)
    text.gsub(SOCIAL_LABEL_HANDLE_RX) do
      platform = Regexp.last_match(1)
      handle = Regexp.last_match(2)
      url = social_profile_url_for_handle(platform, handle)
      next Regexp.last_match(0) if url.empty?

      "#{platform}: #{format_inline_external_link(url, handle)}"
    end
  end

  def linkify_social_handles_in_html(html)
    inside_anchor = false

    html.to_s.split(HTML_TOKEN_RX).map do |part|
      if part.start_with?("<")
        inside_anchor = true if part.match?(/<\s*a[\s>]/i)
        inside_anchor = false if part.match?(/<\s*\/\s*a\s*>/i)
        part
      elsif inside_anchor
        part
      else
        linkify_social_handles_in_text(part)
      end
    end.join
  end

  BLOCK_ELEMENT_RX = /<(p|ul|ol|div|h[1-6])(\s[^>]*)?>([\s\S]*?)<\/\1>/im.freeze
  BLOCK_OPEN_RX = /<(p|ul|ol|div|h[1-6])(\s[^>]*)?>/i.freeze
  SECTION_LABEL_SPLIT_RX = /
    (?=
      \b(?:Show\s+Notes|Episode\s+Sponsors?|Sponsors?|Links|Connect|Resources|
           Topics\s+covered|Timestamps|Chapters|BPC\s*-\s*Brand,\s*Product,\s*Content|
           (?:[A-Z][A-Za-z0-9'’&.-]{0,24}\s+){0,3}Links)
      \s*:
    )
  /ix.freeze

  def strip_presentation_attributes(html)
    cleaned = html.to_s.gsub(/<(p|li|ul|ol|div|h[1-6])(\s+)([^>]*)>/i) do
      tag = Regexp.last_match(1)
      attrs = Regexp.last_match(3).to_s.gsub(
        /\s*(?:style|class|data-[a-z0-9_-]+)=("[^"]*"|'[^']*'|[^\s>]+)/i,
        ""
      ).strip
      attrs.empty? ? "<#{tag}>" : "<#{tag} #{attrs}>"
    end

    cleaned.gsub(/<a(\s+)([^>]*)>/i) do
      attrs = Regexp.last_match(2).to_s
      attrs = attrs.gsub(/\s*(?:style|class|data-[a-z0-9_-]+)=("[^"]*"|'[^']*'|[^\s>]+)/i, "")
      attrs = attrs.gsub(/\btarget=(["'])_new\1/i, 'target="_blank"')
      attrs = attrs.gsub(/\s+/, " ").strip
      attrs.empty? ? "<a>" : "<a #{attrs}>"
    end
  end

  def plain_fragment(html)
    strip_nbsp_entities(CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, " ")))
      .gsub(/\s+/, " ")
      .strip
  end

  def section_header_fragment?(plain, _html)
    return false if plain.empty? || plain.length > 90
    return false unless plain.match?(/\A.+:\s*\z/)
    return false if plain.match?(/:\s*(?:https?|www\.)/i)
    return false if plain.match?(/\|\s*(?:https?|www\.)/i)

    true
  end

  def list_item_fragment?(plain, html)
    return false if plain.empty?
    return false if plain.match?(/\A.+:\s*\z/) && !plain.match?(/:\s*(?:https?|www\.)/i)

    return true if plain.match?(/\A[^|]{1,80}\|\s*\S/i)
    if plain.match?(/\A[^:]{1,80}:\s*\S/i) &&
       (html.match?(/<a[\s>]/i) || plain.match?(%r{https?://|www\.}i))
      return true
    end

    if plain.match?(
         /\b(?:use code|use this link|go to|shop at|subscribe to|join us|follow us|meet us|available at)\b/i
       ) && plain.match?(%r{https?://|www\.}i)
      return true
    end

    plain.length <= 260 && html.match?(/<a[\s>]/i) && plain.match?(%r{https?://|www\.}i)
  end

  def format_section_header(inner)
    plain = plain_fragment(inner)
    label = plain.sub(/:\s*\z/, "")
    %(<p><strong>#{CGI.escapeHTML(label)}:</strong></p>)
  end

  def format_list_item(inner)
    %(<li>#{inner.strip}</li>)
  end

  def format_external_link(href, label)
    safe_href = CGI.escapeHTML(href.to_s.strip)
    safe_label = CGI.escapeHTML(label.to_s.strip)
    favicon = favicon_url_for_link(href, label)
    icon_markup =
      if favicon.empty?
        ""
      else
        %(<img class="episode-note-link__icon" src="#{CGI.escapeHTML(favicon)}" alt="" width="16" height="16" loading="lazy" decoding="async">)
      end
    %(<a href="#{safe_href}" class="episode-note-link" rel="noopener noreferrer" target="_blank">#{icon_markup}<span class="episode-note-link__label">#{safe_label}</span></a>)
  end

  def favicon_domain_from_href(href)
    host = URI.parse(href.to_s.strip).host.to_s.downcase
    host.sub(/\Awww\./, "")
  rescue URI::InvalidURIError
    ""
  end

  def favicon_domain_for_link(href, label)
    label_lower = label.to_s.downcase
    return "instagram.com" if label_lower.include?("instagram")
    return "youtube.com" if label_lower.match?(/youtube|youtu\.be/)
    return "linkedin.com" if label_lower.include?("linkedin")
    return "spotify.com" if label_lower.include?("spotify")
    return "podcasts.apple.com" if label_lower.match?(/apple podcasts|podcasts\.apple/)
    return "strava.com" if label_lower.include?("strava")
    return "x.com" if label_lower.match?(/\btwitter\b|\bx\.com\b/)
    return "facebook.com" if label_lower.include?("facebook")
    return "tiktok.com" if label_lower.include?("tiktok")

    domain = favicon_domain_from_href(href)
    domain.empty? ? nil : domain
  end

  def favicon_url_for_link(href, label)
    domain = favicon_domain_for_link(href, label)
    return "" if domain.to_s.strip.empty?

    "https://www.google.com/s2/favicons?domain=#{CGI.escape(domain)}&sz=32"
  end

  # "Tommie Runz: https://example.com" → linked label only (URL hidden).
  def compact_label_url_link(fragment)
    text = fragment.to_s.strip
    return fragment if text.empty?

    if text.match?(/<a[\s>]/i)
      match = text.match(/\A([^:<\n|]{1,120}?)\s*(?::|\|)\s*(<a\s+[\s\S]*?<\/a>)\s*\z/im)
      if match
        label = plain_fragment(match[1]).strip
        href_match = match[2].match(/href\s*=\s*(["'])(.*?)\1/im)
        return format_external_link(href_match[2], label) if href_match && !label.empty?
      end
    end

    plain = plain_fragment(text)
    url_match = plain.match(/\A([^:\n|]{1,120}?)\s*(?::|\|)\s*((?:https?:\/\/|www\.)\S+)\z/i)
    if url_match
      label = url_match[1].strip
      url = url_match[2]
      url, = strip_trailing_url_punctuation(url)
      return format_external_link(normalize_autolink_href(url), label) unless label.empty?
    end

    fragment
  end

  def compact_label_url_links_in_html(html)
    html.to_s.gsub(/<(li|p)(\s[^>]*)?>([\s\S]*?)<\/\1>/im) do
      tag = Regexp.last_match(1)
      attrs = Regexp.last_match(2).to_s
      inner = Regexp.last_match(3).to_s.strip
      compacted = compact_label_url_link(inner)
      compacted == inner ? Regexp.last_match(0) : "<#{tag}#{attrs}>#{compacted}</#{tag}>"
    end
  end

  def split_block_elements_on_breaks(html)
    html.gsub(BLOCK_ELEMENT_RX) do
      tag = Regexp.last_match(1)
      attrs = Regexp.last_match(2).to_s
      inner = Regexp.last_match(3).to_s
      next Regexp.last_match(0) unless %w[p div].include?(tag.downcase)
      next Regexp.last_match(0) unless inner.match?(/<br\s*\/?>/i)

      parts = inner.split(/<br\s*\/?>/i).map(&:strip).reject { |part| html_inner_blank?(part) }
      next Regexp.last_match(0) if parts.length <= 1

      parts.map { |part| "<#{tag}#{attrs}>#{part}</#{tag}>" }.join
    end
  end

  def split_leading_text_segments(text)
    text.to_s.strip.split(SECTION_LABEL_SPLIT_RX).map(&:strip).reject(&:empty?)
  end

  def each_description_segment(html)
    rest = html.to_s
    until rest.empty?
      if (block_match = rest.match(/\A\s*<(p|ul|ol|div|h[1-6])(\s[^>]*)?>[\s\S]*?<\/\1>/im))
        yield :element, block_match[1].downcase, block_match[0]
        rest = rest[block_match[0].length..]
        next
      end

      next_block = rest.match(BLOCK_OPEN_RX)
      if next_block
        text = rest[0, next_block.begin(0)].strip
        unless text.empty?
          split_leading_text_segments(text).each do |segment|
            yield :text, segment
          end
        end
        rest = rest[next_block.begin(0)..]
        next
      end

      split_leading_text_segments(rest).each do |segment|
        yield :text, segment
      end
      break
    end
  end

  def classify_segment(plain, html_inner)
    return :header if section_header_fragment?(plain, html_inner)
    return :list_item if list_item_fragment?(plain, html_inner)

    :prose
  end

  def normalize_list_element_html(tag, element_html)
    inner = element_html.match(BLOCK_ELEMENT_RX)&.captures&.last.to_s
    inner.gsub(/<li(\s[^>]*)?>([\s\S]*?)<\/li>/im) do
      li_inner = Regexp.last_match(2).to_s.strip
      if (bare = li_inner.match(/\A<p(\s[^>]*)?>([\s\S]*?)<\/p>\z/im))
        li_inner = bare[2].to_s.strip
      end
      format_list_item(li_inner)
    end.then { |items| "<#{tag}>#{items}</#{tag}>" }
  end

  def structure_episode_description_html(html)
    cleaned = strip_presentation_attributes(html.to_s)
    cleaned = split_block_elements_on_breaks(cleaned)

    output = []
    list_buffer = []

    flush_list = lambda do
      next if list_buffer.empty?

      output << "<ul>#{list_buffer.join}</ul>"
      list_buffer.clear
    end

    process_inner = lambda do |inner|
      plain = plain_fragment(inner)
      case classify_segment(plain, inner)
      when :header
        flush_list.call
        output << format_section_header(inner)
      when :list_item
        list_buffer << format_list_item(inner)
      else
        flush_list.call
        output << "<p>#{inner.strip}</p>"
      end
    end

    each_description_segment(cleaned) do |kind, value, element_html = nil|
      case kind
      when :text
        plain = plain_fragment(value)
        inner = value.match?(/<[^>]+>/) ? value : CGI.escapeHTML(plain)
        process_inner.call(inner)
      when :element
        tag = value
        if tag == "ul" || tag == "ol"
          flush_list.call
          output << normalize_list_element_html(tag, element_html)
        elsif tag.start_with?("h")
          flush_list.call
          plain = plain_fragment(element_html.match(BLOCK_ELEMENT_RX)&.captures&.last)
          output << format_section_header(plain)
        else
          inner = element_html.match(BLOCK_ELEMENT_RX)&.captures&.last.to_s
          process_inner.call(inner)
        end
      end
    end

    flush_list.call
    structured = output.join
    structured.empty? ? cleaned : structured
  end

  def sanitize_episode_description_html(html)
    cleaned = html.to_s.strip
    return "" if cleaned.empty?

    cleaned = cleaned.gsub(/\r\n?/, "\n")
    cleaned = strip_paragraphs_with_only_nbsp(cleaned)
    cleaned = strip_nbsp_entities(cleaned)

    cleaned = strip_empty_block_tags(cleaned)

    loop do
      next_html = cleaned.gsub(/<p(\s[^>]*)?>\s*<\/p>/i, "")
      break if next_html == cleaned

      cleaned = next_html
    end

    cleaned = cleaned.gsub(/<(p|div|li)(\s[^>]*)?>\s+/, '<\1\2>')
    cleaned = cleaned.gsub(/\s+<\/(p|div|li)>/, "</\\1>")
    cleaned = cleaned.gsub(/>\s+</, "><")
    cleaned = structure_episode_description_html(cleaned)
    cleaned = cleaned.gsub(/<br\s*\/?>/i, " ")
    cleaned = repair_split_word_links(cleaned)
    cleaned = linkify_bare_urls_in_html(cleaned.strip)
    cleaned = linkify_social_handles_in_html(cleaned)
    compact_label_url_links_in_html(cleaned)
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

  def latest_episode_row_for_doc(doc, episodes)
    latest_episode_meta = Array(episodes).find { |episode| episode.is_a?(Hash) }
    return nil unless latest_episode_meta

    audio_url = latest_episode_meta["audio_url"].to_s.strip
    title = latest_episode_meta["episode_title"].to_s.strip
    return nil if audio_url.empty? || title.empty?

    {
      "podcast_title" => doc.data["title"],
      "podcast_page_url" => doc.url,
      "cover_image" => doc.data["cover_image"].to_s.strip,
      "feed_url" => doc.data["rss_feed"].to_s.strip,
      "filter_category" => filter_category_for_doc(doc),
      "episode_title" => title,
      "episode_url" => latest_episode_meta["episode_url"].to_s.strip,
      "audio_url" => audio_url,
      "published_at" => latest_episode_meta["published_at"],
      "episode_key" => latest_episode_meta["episode_slug"],
      "episode_slug" => latest_episode_meta["episode_slug"],
      "episode_page_url" => latest_episode_meta["episode_page_url"]
    }
  end

  def non_running_items_for_site(site, episodes_by_feed)
    return [] unless episodes_by_feed.is_a?(Hash)

    podcast_posts_with_feed(site)
      .select { |doc| doc.data["not_running_related"] == true }
      .map do |doc|
        feed_key = normalize_feed_key(doc.data["rss_feed"])
        latest_episode_row_for_doc(doc, episodes_by_feed[feed_key])
      end
      .compact
      .sort_by do |item|
        begin
          Time.parse(item["published_at"].to_s)
        rescue ArgumentError, TypeError
          Time.at(0)
        end
      end
      .reverse
  end

  # ASCII-only URL segments: transliterate æ→ae, ø→o, å→a, é→e, etc. (I18n + Jekyll "latin" mode).
  def slugify_segment(text, mode: "latin")
    return "" if text.to_s.strip.empty?

    Jekyll::Utils.slugify(text.to_s, mode: mode)
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

  def episode_slug_for_title(title, published_at: nil, used_slugs: [], slugify_mode: "latin")
    base = slugify_segment(title.to_s, mode: slugify_mode)
    if base.empty? && published_at
      base = slugify_segment(published_at.strftime("%Y-%m-%d"), mode: slugify_mode)
    end
    base = "episode" if base.empty?
    base = base[0, 120]

    slug = base
    suffix = 2
    while used_slugs.include?(slug)
      slug = "#{base}-#{suffix}"
      suffix += 1
    end
    used_slugs << slug if slugify_mode == "latin"
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
      slug = episode_slug_for_title(title, published_at: published_at, used_slugs: used_slugs, slugify_mode: "latin")
      unicode_slug =
        episode_slug_for_title(title, published_at: published_at, used_slugs: [], slugify_mode: "default")
      entry["episode_slug"] = slug
      entry["episode_key"] = slug
      entry["legacy_unicode_slug"] = unicode_slug if unicode_slug != slug
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
      LatestPodcastEpisodes.resanitize_episode_descriptions!(merged["episodes_by_feed"])
      merged["non_running_items"] = LatestPodcastEpisodes.non_running_items_for_site(
        site,
        merged["episodes_by_feed"]
      )
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
  LatestPodcastEpisodes.resanitize_episode_descriptions!(episodes_by_feed)

  feeds_with_episodes = episodes_by_feed.count do |_, episodes|
    episodes.is_a?(Array) && !episodes.empty?
  end
  has_episodes_by_feed = feeds_with_episodes.positive?

  payload = {
    "generated_at" => Time.now.utc.iso8601,
    "items" => sorted,
    "non_running_items" => LatestPodcastEpisodes.non_running_items_for_site(site, episodes_by_feed),
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
      "non_running_items" => LatestPodcastEpisodes.non_running_items_for_site(site, cached["episodes_by_feed"]),
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
      "fetch_errors" => errors,
      "non_running_items" => LatestPodcastEpisodes.non_running_items_for_site(site, prior_snapshot["episodes_by_feed"])
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
