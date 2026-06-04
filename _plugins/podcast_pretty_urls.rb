# frozen_string_literal: true

# Podcast directory posts use clean URLs (/show-name/) instead of /show-name.html.
# Adds redirect_from for legacy .html paths (and -md.html when applicable).

Jekyll::Hooks.register :site, :post_read, priority: :low do |site|
  posts = site.collections["posts"]&.docs
  next unless posts

  posts.each do |doc|
    next unless doc.relative_path&.start_with?("_posts/podcasts/")
    next unless doc.data["category"] == "podcast"

    slug = doc.data["slug"].to_s.strip
    next if slug.empty?

    new_path = "/#{slug}/"
    doc.data["permalink"] = new_path

    legacy_paths = ["/#{slug}.html"]

    case doc.data["redirect_from"]
    when nil, false
      doc.data["redirect_from"] = legacy_paths.uniq
    when Array
      doc.data["redirect_from"] = (doc.data["redirect_from"] + legacy_paths).uniq
    when String
      doc.data["redirect_from"] = ([doc.data["redirect_from"]] + legacy_paths).uniq
    end

    %i[@url @url_placeholders @destination @id @to_liquid].each do |iv|
      doc.remove_instance_variable(iv) if doc.instance_variable_defined?(iv)
    end
  end
end
