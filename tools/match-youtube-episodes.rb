#!/usr/bin/env ruby
# frozen_string_literal: true

# Match podcast episodes to YouTube uploads and write youtube_video_id into
# _data/latest_podcast_episodes.yml. Runs outside Jekyll so CI does not depend
# on generator ordering or fetch timing inside the build.

require "fileutils"
require "yaml"

ROOT = File.expand_path("..", __dir__)
EPISODE_DATA_PATH = File.join(ROOT, "_data", "latest_podcast_episodes.yml")
PODCASTS_GLOB = File.join(ROOT, "_posts", "podcasts", "*.md")

class MatchSite
  def in_source_dir(*parts)
    File.join(ROOT, *parts)
  end
end

class PodcastDoc
  attr_reader :data

  def initialize(data)
    @data = data
  end
end

# youtube_episode_matcher.rb logs via Jekyll.logger; stub it for standalone runs.
module Jekyll
  class << self
    def logger
      @standalone_logger ||= Class.new do
        def warn(*parts)
          Kernel.warn(parts.join(": "))
        end

        def info(*parts)
          puts parts.join(": ")
        end

        def debug(*parts)
        end
      end.new
    end
  end
end

module LatestPodcastEpisodes
  module_function

  def episode_pages_build?
    ENV["EPISODE_PAGES_BUILD"].to_s == "1"
  end

  def rss_fetch_enabled?
    ENV["JEKYLL_FETCH_RSS"].to_s == "1"
  end

  def normalize_feed_key(url)
    url.to_s.strip.downcase
  end

  def youtube_only_podcast?(doc)
    data = doc.respond_to?(:data) ? doc.data : {}
    data["rss_feed"].to_s.strip.empty? && data["youtube_link"].to_s.strip != ""
  end

  def feed_to_podcast_map(_site)
    map = {}
    Dir.glob(PODCASTS_GLOB).sort.each do |path|
      data = read_front_matter(path)
      next unless data["category"].to_s == "podcast"

      feed_url = data["rss_feed"].to_s.strip
      next if feed_url.empty?
      next if data["youtube_link"].to_s.strip.empty?

      map[normalize_feed_key(feed_url)] = PodcastDoc.new(data)
    end
    map
  end

  def write_committed_data(_site, payload)
    return unless ENV["JEKYLL_ENV"].to_s == "production" || ENV["YOUTUBE_MATCH"].to_s == "1"

    yaml =
      if YAML.respond_to?(:dump)
        begin
          YAML.dump(payload, line_width: -1, alias: false)
        rescue ArgumentError
          YAML.dump(payload)
        end
      else
        YAML.dump(payload)
      end
    File.write(EPISODE_DATA_PATH, yaml)
  end

  def read_front_matter(path)
    content = File.read(path)
    return {} unless content.start_with?("---")

    _, yaml, = content.split("---", 3)
    YAML.safe_load(yaml, permitted_classes: [Time, Date], aliases: true) || {}
  rescue StandardError
    {}
  end
end

require_relative "../_plugins/youtube_episode_matcher"

def load_episode_data
  YAML.safe_load(File.read(EPISODE_DATA_PATH), permitted_classes: [Time, Date], aliases: true)
end

def main
  unless YoutubeEpisodeMatcher.fetch_enabled?
    warn "YoutubeEpisodeMatcher: fetch disabled (set YOUTUBE_MATCH=1 or EPISODE_PAGES_BUILD=1)"
    exit 0
  end

  payload = load_episode_data
  unless payload.is_a?(Hash) && payload["episodes_by_feed"].is_a?(Hash)
    warn "YoutubeEpisodeMatcher: missing episodes_by_feed in #{EPISODE_DATA_PATH}"
    exit 1
  end

  site = MatchSite.new
  feed_to_podcast = LatestPodcastEpisodes.feed_to_podcast_map(site)
  matched =
    YoutubeEpisodeMatcher.enrich_episodes_by_feed!(
      site,
      payload["episodes_by_feed"],
      feed_to_podcast
    )

  if matched.positive?
    LatestPodcastEpisodes.write_committed_data(site, payload)
    puts "YoutubeEpisodeMatcher: matched #{matched} episode(s); updated #{EPISODE_DATA_PATH}"
  else
    puts "YoutubeEpisodeMatcher: 0 assignments (feeds=#{feed_to_podcast.size})"
  end
end

main if $PROGRAM_NAME == __FILE__
