# frozen_string_literal: true

require_relative "latest_podcast_episodes"

module EpisodeDurationFilter
  def format_episode_duration(seconds)
    total = seconds.to_i
    return "" if total <= 0

    LatestPodcastEpisodes.format_chapter_clock(total)
  end

  def episode_duration_iso8601(seconds)
    total = seconds.to_i
    return "" if total <= 0

    LatestPodcastEpisodes.chapter_time_iso8601(total)
  end
end

Liquid::Template.register_filter(EpisodeDurationFilter)
