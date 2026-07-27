#!/usr/bin/env ruby
# Regenerate docs/latest-episodes/index.html episode list from committed _data.
# Use when episode data was updated but the latest-episodes page was not rebuilt.
require "yaml"
require "cgi"
require "time"

ROOT = File.expand_path("..", __dir__)
DATA_PATH = File.join(ROOT, "_data", "latest_podcast_episodes.yml")
HTML_PATH = File.join(ROOT, "docs", "latest-episodes", "index.html")
LIMIT = 100

def html_attr(value)
  CGI.escapeHTML(value.to_s)
end

def picture_tag(cover)
  src = cover.start_with?("/") ? cover : "/media/#{cover}"
  webp = src.sub(/\.(jpe?g|png)\z/i, ".webp")
  <<~HTML.strip
    <picture><source type="image/webp" srcset="#{html_attr(webp)}" /><img fetchpriority="high" decoding="async" src="#{html_attr(src)}" alt="" class="latest-episodes__cover" decoding="async" width="40" height="40" loading="lazy" /></picture>
  HTML
end

def player_picture_tag(cover)
  src = cover.start_with?("/") ? cover : "/media/#{cover}"
  webp = src.sub(/\.(jpe?g|png)\z/i, ".webp")
  <<~HTML.strip
    <picture><source type="image/webp" srcset="#{html_attr(webp)}" /><img fetchpriority="high" decoding="async" src="#{html_attr(src)}" alt="" class="latest-episodes__player-art" data-player-art="" decoding="async" width="96" height="96" loading="lazy" /></picture>
  HTML
end

def format_date(iso)
  Time.parse(iso.to_s).strftime("%b %-d, %Y")
rescue ArgumentError, TypeError
  ""
end

def episode_li(episode)
  category = episode["filter_category"].to_s.strip
  podcast_url = episode["podcast_page_url"].to_s
  cover = episode["cover_image"].to_s
  title = episode["episode_title"].to_s
  audio = episode["audio_url"].to_s
  episode_url = episode["episode_page_url"].to_s
  podcast_title = episode["podcast_title"].to_s
  date_label = format_date(episode["published_at"])
  cover_attr = cover.start_with?("/") ? cover : "/media/#{cover}"

  category_attr = category != "" ? %( data-category="#{html_attr(category)}") : ""
  podcast_attr = podcast_url != "" ? %( data-podcast-url="#{html_attr(podcast_url)}") : ""
  cover_data = cover != "" ? %( data-cover-url="#{html_attr(cover_attr)}") : ""
  episode_data = episode_url != "" ? %( data-episode-url="#{html_attr(episode_url)}") : ""
  podcast_data = podcast_url != "" ? %( data-podcast-url="#{html_attr(podcast_url)}") : ""

  art_html =
    if cover != ""
      %(<span class="latest-episodes__play-art" aria-hidden="true">#{picture_tag(cover)}</span>)
    else
      %(<span class="latest-episodes__play-art" aria-hidden="true"><span class="latest-episodes__play-art-placeholder"></span></span>)
    end

  podcast_link =
    if podcast_url != ""
      %(<a href="#{html_attr(podcast_url)}" class="latest-episodes__podcast-link">#{html_attr(podcast_title)}</a>)
    else
      html_attr(podcast_title)
    end

  date_suffix = date_label != "" ? " • #{html_attr(date_label)}" : ""

  <<~HTML.strip
    <li class="latest-episodes__item"#{category_attr}#{podcast_attr}>
      <div class="latest-episodes__episode-stack">
        <button type="button" class="latest-episodes__play latest-episodes__play--art" aria-pressed="false" aria-label="Play episode: #{html_attr(title)}" data-audio-url="#{html_attr(audio)}" data-episode-title="#{html_attr(title)}" data-podcast-title="#{html_attr(podcast_title)}"#{cover_data}#{episode_data}#{podcast_data}>
          #{art_html}
          <span class="latest-episodes__play-glyph" aria-hidden="true"></span>
        </button>
        <div class="latest-episodes__episode-copy">
        <a href="#{html_attr(episode_url)}" class="latest-episodes__episode-title latest-episodes__episode-title--row">#{html_attr(title)}</a>
        <p class="latest-episodes__meta latest-episodes__meta--stacked">#{podcast_link}#{date_suffix}
        </p>
        </div>
      </div>
      <div class="latest-episodes__listen-track" data-listen-progress-track="" hidden="">
        <div class="latest-episodes__listen-fill" data-listen-progress="" style="width: 0%"></div>
      </div>
    </li>
  HTML
end

data = YAML.load_file(DATA_PATH)
items = Array(data["items"]).first(LIMIT)
abort "No items in #{DATA_PATH}" if items.empty?

html = File.read(HTML_PATH)
list_start = html.index('<ol class="latest-episodes__list">')
list_end = html.index("</ol>", list_start)
abort "Could not find episode list in #{HTML_PATH}" unless list_start && list_end

empty_li = <<~HTML.strip
  <li class="latest-episodes__empty" role="status" aria-live="polite" hidden="">
    <p>No episodes match these filters. Try clearing filters or choose fewer categories.</p>
  </li>
HTML

new_list = +'<ol class="latest-episodes__list">'
new_list << empty_li
items.each { |episode| new_list << episode_li(episode) }
new_list << "</ol>"

html[list_start..list_end + 4] = new_list

first_cover = items.first["cover_image"].to_s
first_cover = first_cover.start_with?("/") ? first_cover : "/media/#{first_cover}"
if first_cover != ""
  html.sub!(
    /data-default-cover="[^"]*"><picture>.*?<\/picture><\/div>/m,
    %(data-default-cover="#{html_attr(first_cover)}">#{player_picture_tag(first_cover)}</div>)
  )
end

File.write(HTML_PATH, html)
puts "Updated #{HTML_PATH} with #{items.size} episodes (includes #{items.map { |i| i['podcast_title'] }.uniq.join(', ')})"
