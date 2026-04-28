# frozen_string_literal: true

# When `cover_image` is absent, set it from the first Markdown image pointing at `/media/...`
# (supports `](/media/foo)` or `]({{site.baseurl}}/media/foo)`).
# Improves Open Graph, Twitter cards, and PodcastSeries JSON-LD without manual front matter.
FIRST_MEDIA_IMG = /\]\(\s*(?:\{\{\s*site\.baseurl\s*\}\})?\s*(\/media\/[^)\s]+)/m.freeze

Jekyll::Hooks.register :documents, :pre_render do |doc, _payload|
  next unless doc.output_ext == ".html"
  next unless doc.collection&.label == "posts"
  next unless doc.relative_path&.include?("_posts/podcasts/")

  data = doc.data
  next if data["cover_image"].to_s.strip != ""

  m = doc.content.to_s.match(FIRST_MEDIA_IMG)
  data["cover_image"] = m[1].strip if m
end
