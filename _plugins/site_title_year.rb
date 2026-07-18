# frozen_string_literal: true

# Appends the build year to site.title and site.heading (e.g. "The Best Running Podcasts 2026").

module SiteTitleYear
  YEAR_SUFFIX = /\s+\d{4}\z/.freeze

  module_function

  def with_current_year(name)
    base = name.to_s.strip.sub(YEAR_SUFFIX, "")
    return "" if base.empty?

    "#{base} #{Time.now.utc.year}"
  end
end

Jekyll::Hooks.register :site, :after_init do |site|
  base_title = site.config["title"].to_s.strip.sub(SiteTitleYear::YEAR_SUFFIX, "")
  base_title = "The Best Running Podcasts" if base_title.empty?

  full_title = SiteTitleYear.with_current_year(base_title)
  site.config["title"] = full_title
  site.config["title_base"] = base_title

  heading = site.config["heading"].to_s.strip
  base_heading = heading.sub(SiteTitleYear::YEAR_SUFFIX, "")
  if heading.empty? || base_heading == base_title
    site.config["heading"] = full_title
    site.config["heading_base"] = base_title
  else
    site.config["heading"] = SiteTitleYear.with_current_year(heading)
    site.config["heading_base"] = base_heading
  end
end
