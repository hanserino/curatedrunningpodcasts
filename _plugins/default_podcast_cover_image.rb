# frozen_string_literal: true

require "uri"

# - `explicit_cover_image` is true when front matter yields a usable `cover_image` string
#   (plain path, Decap object with `path`, or array) before inference.
# - Decap may store uploads as YAML strings (`/media/...`), hashes (`path:`), or absolute URLs —
#   we coerce to `/media/...` for Liquid and OG.
# - `infer_cover_from_body`: first markdown line is `/media/` image — legacy thumbnail in body only.
FIRST_MEDIA_IMG = Regexp.compile('\]\(\s*(?:\{\{[^}]*\}\})?\s*(/media/[^\s)]+)', Regexp::MULTILINE).freeze
MD_FIRST_IMG_LINE = Regexp.compile('\A[ \t]*!\[[^\]]*\]\(\s*(?:\{\{[^}]*\}\})?\s*(/media/[^\s)]+)\s*\)[ \t]*(?:\r?\n|\z)', Regexp::MULTILINE).freeze

def self.extract_cover_from_front_matter(raw)
  case raw
  when nil then nil
  when String
    s = raw.to_s.strip
    s.empty? ? nil : s
  when Hash
    v = raw["path"] || raw[:path] || raw["file"] || raw["src"] || raw[:src] || raw["url"] || raw[:url]
    extract_cover_from_front_matter(v)
  when Array
    extract_cover_from_front_matter(raw[0])
  else
    s = raw.to_s.strip
    s.empty? ? nil : s
  end
end

def self.normalize_cover_path(raw, site_url = nil)
  s = extract_cover_from_front_matter(raw) || ""
  return "" if s.empty?

  # Absolute URL → path (handles Decap/GitHub CDN links and dev vs prod hosts)
  if s.match?(/\Ahttps?:\/\//i)
    begin
      u = URI.parse(s)
      s = u.path.to_s
    rescue URI::InvalidURIError
      return ""
    end
    return "" if s.empty?
  elsif site_url && !site_url.to_s.empty?
    base = site_url.to_s.chomp("/")
    if s.start_with?("#{base}/")
      s = s[base.length..]
    end
  end

  s = s.to_s.strip
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
  site_url = doc.site.config["url"]

  extracted = extract_cover_from_front_matter(data["cover_image"])
  explicit_fm = !extracted.nil?
  data["explicit_cover_image"] = explicit_fm

  if explicit_fm
    data["cover_image"] = self.normalize_cover_path(extracted, site_url)
    if (md = content_str.match(MD_FIRST_IMG_LINE)) && self.normalize_cover_path(md[1].to_s, site_url) == data["cover_image"]
      doc.content = content_str.sub(MD_FIRST_IMG_LINE, "")
    end
  elsif (m = content_str.match(MD_FIRST_IMG_LINE))
    data["cover_image"] = self.normalize_cover_path(m[1].to_s, site_url)
    data["infer_cover_from_body"] = true
  elsif (m2 = content_str.match(FIRST_MEDIA_IMG))
    data["cover_image"] = self.normalize_cover_path(m2[1].to_s, site_url)
  end
end
