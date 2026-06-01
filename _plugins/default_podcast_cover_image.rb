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

def self.mime_type_for_path(path)
  case File.extname(path.to_s).downcase
  when ".jpg", ".jpeg" then "image/jpeg"
  when ".png" then "image/png"
  when ".webp" then "image/webp"
  when ".gif" then "image/gif"
  else "image/jpeg"
  end
end

def self.read_png_dimensions(path)
  File.open(path, "rb") do |io|
    return nil unless io.read(8)
    chunk = io.read(8)
    return nil unless chunk && chunk.bytesize == 8
    chunk.unpack("NN")
  end
rescue StandardError
  nil
end

def self.read_gif_dimensions(path)
  File.open(path, "rb") do |io|
    io.read(6)
    chunk = io.read(4)
    return nil unless chunk && chunk.bytesize == 4
    chunk.unpack("vv")
  end
rescue StandardError
  nil
end

def self.read_jpeg_dimensions(path)
  File.open(path, "rb") do |io|
    return nil unless io.read(2) == "\xFF\xD8".b
    while (byte = io.read(1))
      next unless byte.bytes[0] == 0xFF
      marker_byte = io.read(1)
      break unless marker_byte
      marker = marker_byte.bytes[0]
      break if marker == 0xD9
      len_bytes = io.read(2)
      break unless len_bytes && len_bytes.bytesize == 2
      len = len_bytes.unpack1("n")
      break unless len && len >= 2
      if marker >= 0xC0 && marker <= 0xCF && ![0xC4, 0xC8, 0xCC].include?(marker)
        data = io.read(5)
        return nil unless data && data.bytesize == 5
        h, w = data.byteslice(1, 4).unpack("nn")
        return [w, h]
      end
      io.read(len - 2)
    end
  end
  nil
rescue StandardError
  nil
end

def self.read_webp_dimensions(path)
  File.open(path, "rb") do |io|
    header = io.read(12)
    return nil unless header && header.start_with?("RIFF") && header.byteslice(8, 4) == "WEBP"
    chunk_header = io.read(8)
    return nil unless chunk_header && chunk_header.bytesize == 8
    case chunk_header.byteslice(0, 4)
    when "VP8 "
      frame = io.read(10)
      return nil unless frame && frame.bytesize == 10
      w = frame.byteslice(6, 2).unpack1("v") & 0x3FFF
      h = frame.byteslice(8, 2).unpack1("v") & 0x3FFF
      [w, h]
    when "VP8L"
      data = io.read(5)
      return nil unless data && data.bytesize == 5
      n = data.byteslice(1, 4).unpack1("V")
      w = (n & 0x3FFF) + 1
      h = ((n >> 14) & 0x3FFF) + 1
      [w, h]
    when "VP8X"
      ext = io.read(10)
      return nil unless ext && ext.bytesize == 10
      b = ext.bytes
      w = (b[4] | (b[5] << 8) | (b[6] << 16)) + 1
      h = (b[7] | (b[8] << 8) | (b[9] << 16)) + 1
      [w, h]
    end
  end
  nil
rescue StandardError
  nil
end

def self.image_dimensions(abs_path)
  return nil unless File.file?(abs_path)
  case File.extname(abs_path).downcase
  when ".png" then read_png_dimensions(abs_path)
  when ".jpg", ".jpeg" then read_jpeg_dimensions(abs_path)
  when ".webp" then read_webp_dimensions(abs_path)
  when ".gif" then read_gif_dimensions(abs_path)
  end
end

def self.assign_og_image_meta(data, site_source)
  cover = data["cover_image"].to_s.strip
  return if cover.empty?

  rel = cover.delete_prefix("/")
  abs = File.join(site_source, rel)
  dims = image_dimensions(abs)
  return unless dims

  data["og_image_width"], data["og_image_height"] = dims
  data["og_image_type"] = mime_type_for_path(cover)
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

  assign_og_image_meta(data, doc.site.source)
end
