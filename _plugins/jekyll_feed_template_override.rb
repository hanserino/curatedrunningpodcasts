# frozen_string_literal: true

# Use _includes/feed.xml when present (filters not_running_related posts from site RSS).
module JekyllFeedTemplateOverride
  def feed_source_path
    custom = @site.in_source_dir("_includes", "feed.xml")
    return custom if File.file?(custom)

    super
  end
end

JekyllFeed::Generator.prepend(JekyllFeedTemplateOverride)
