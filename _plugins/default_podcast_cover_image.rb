# frozen_string_literal: true

# - `cover_image` in front matter (e.g. Decap image widget) → normalized path; used for OG/JSON-LD
#   and for on-page cover when `explicit_cover_image` is true.
# - If `cover_image` is absent, infer URL from the first Markdown image linking to `/media/...`
#   (anywhere in the body) for SEO; set `infer_cover_from_body` when that image is the first line
#   (legacy posts) so the layout keeps a single inline image.
# - Strips a leading duplicate Markdown image line when it matches an explicit `cover_image`.
# Use Regexp.new to avoid %r-delimiter clashes with parentheses in the pattern.
FIRST_MEDIA_IMG = Regexp.compile('\]\(\s*(?:\{\{[^}]*\}\})?\s*(/media/[^\s)]+)', Regexp::MULTILINE).freeze
MD_FIRST_IMG_LINE = Regexp.compile('\A[ \t]*!\[[^\]]*\]\(\s*(?:\{\{[^}]*\}\})?\s*(/media/[^\s)]+)\s*\)[ \t]*(?:\r?\n|\z)', Regexp::MULTILINE).freeze

def self.normalize_cover_path(raw)
  s = raw.to_s.strip
  return "" if s.empty?
  return s if s.start_with?("/media/")
  return "/media/#{s}" unless s.include?("/")
  s.start_with?("/") ? s : "/#{s}"
end

Jekyll::Hooks.register :documents, :pre_render do |doc, _payload|
  next unless doc.output_ext == ".html"
  next unless doc.collection&.label == "posts"
  next unless doc.relative_path&.include?("_posts/podcasts/")

  data = doc.data
  content_str = doc.content.to_s

  explicit = data.key?("cover_image") && data["cover_image"].to_s.strip != ""
  data["explicit_cover_image"] = explicit

  if explicit
    data["cover_image"] = self.normalize_cover_path(data["cover_image"])
    if (md = content_str.match(MD_FIRST_IMG_LINE)) && self.normalize_cover_path(md[1]) == data["cover_image"]
      doc.content = content_str.sub(MD_FIRST_IMG_LINE, "")
    end
  elsif (m = content_str.match(MD_FIRST_IMG_LINE))
    data["cover_image"] = self.normalize_cover_path(m[1])
    data["infer_cover_from_body"] = true
  elsif (m2 = content_str.match(FIRST_MEDIA_IMG))
    data["cover_image"] = self.normalize_cover_path(m2[1])
  end
end
