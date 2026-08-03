#!/usr/bin/env ruby
# frozen_string_literal: true

# Backfill empty episode show notes from RSS using curl (works when Ruby OpenSSL fails locally).
# Updates _data/latest_podcast_episodes.yml in place.

require "open3"
require "yaml"
require "jekyll"

ENV["SKIP_DATA_RESANITIZE"] = "1"

ROOT = File.expand_path("..", __dir__)
require File.join(ROOT, "_plugins/latest_podcast_episodes.rb")

module LatestPodcastEpisodes
  module_function

  def fetch_feed(url)
    xml, status = Open3.capture2(
      "curl", "-sL",
      "--connect-timeout", "10",
      "--max-time", "30",
      "-A", USER_AGENT,
      url
    )
    raise "curl failed for #{url}" unless status.success? && !xml.to_s.strip.empty?

    xml
  end
end

path = File.join(ROOT, "_data/latest_podcast_episodes.yml")
payload = YAML.load_file(path, aliases: true)
episodes_by_feed = payload["episodes_by_feed"]
abort "No episodes_by_feed in #{path}" unless episodes_by_feed.is_a?(Hash)

feeds_to_fetch = episodes_by_feed.select do |_, episodes|
  Array(episodes).any? { |entry| entry.is_a?(Hash) && entry["description_html"].to_s.strip.empty? }
end

puts "Backfilling #{feeds_to_fetch.size} feed(s) with missing show notes..."
updated_feeds = 0
updated_episodes = 0

feeds_to_fetch.each do |feed_url, episodes|
  print "  #{feed_url}... "
  $stdout.flush
  begin
    xml = LatestPodcastEpisodes.fetch_feed(feed_url)
    before = Array(episodes).count { |e| e.is_a?(Hash) && e["description_html"].to_s.strip.empty? }
    LatestPodcastEpisodes.backfill_episodes_from_feed!(episodes, xml)
    after = Array(episodes).count { |e| e.is_a?(Hash) && e["description_html"].to_s.strip.empty? }
    filled = before - after
    if filled.positive?
      updated_feeds += 1
      updated_episodes += filled
      puts "filled #{filled} episode(s)"
    else
      puts "no RSS description available"
    end
  rescue StandardError => e
    puts "failed (#{e.class})"
    warn "    #{e.message}"
  end
end

if updated_episodes.zero?
  puts "No episode descriptions updated."
  exit 0
end

payload["generated_at"] = Time.now.utc.iso8601
stripped = LatestPodcastEpisodes.strip_internal_episode_keys!(payload)
File.write(path, LatestPodcastEpisodes.dump_yaml(stripped))
puts "Updated #{path} (#{updated_feeds} feeds, #{updated_episodes} episodes)."
