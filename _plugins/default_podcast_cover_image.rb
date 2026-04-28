# frozen_string_literal: true

# - `explicit_cover_image` is true only when front matter contained a non-blank `cover_image`
#   before inference (Decap uploads, hand-edited YAML). Used for `<img>` in templates.
# - `infer_cover_from_body`: first line is a markdown image linking to `/media/...`
#   (legacy). Keep a single `<img>` from rendered body — do not also render `cover_image`.
# - Otherwise, `cover_image` may still be set from a later image in the body (SEO only);
#   the loop shows body content only to avoid duplicate thumbnails.
# - Strips a leading duplicate markdown image line when it matches an explicit `cover_image`.
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

  # Snapshot before mutating `cover_image` for inference. Do not use `key?`: YAML `null` or
  # empty string must not count as “explicit”, and some environments differ on key? for nil.
  initial_fm = data["cover_image"]
  explicit_fm = !initial_fm.nil? && !initial_fm.to_s.strip.empty?
  data["explicit_cover_image"] = explicit_fm

  if explicit_fm
    data["cover_image"] = self.normalize_cover_path(initial_fm.to_s)
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
