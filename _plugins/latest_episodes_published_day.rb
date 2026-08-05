# frozen_string_literal: true

require "time"

# Stamp UTC published_day on latest-episode items so day headers stay contiguous
# with absolute-time sort. Liquid's date filter keeps publisher offsets (e.g. +10:00),
# which reopens Today/Yesterday groups.
class LatestEpisodesPublishedDay < Jekyll::Generator
  safe true
  priority :high

  def generate(site)
    payload = site.data["latest_podcast_episodes"]
    return unless payload.is_a?(Hash)

    Array(payload["items"]).each do |item|
      next unless item.is_a?(Hash)

      raw = item["published_at"]
      next if raw.nil? || (raw.respond_to?(:empty?) && raw.empty?)

      time = raw.is_a?(Time) ? raw : Time.parse(raw.to_s)
      item["published_day"] = time.utc.strftime("%Y-%m-%d")
    rescue ArgumentError, TypeError
      # leave published_day unset; template falls back to published_at
    end
  end
end
