# frozen_string_literal: true

# Decap may produce filenames like `YYYY-MM-DD-show-name-md.md` (slug includes a literal
# "-md" before .md). Jekyll would then emit `/show-name-md.html`. We normalize the URL to
# `/show-name.html` when permalink is still the default template (`/:slug.html`), set
# redirect_from for the old path, and adjust data["slug"].
#
# Runs at :site :post_read so data is merged and jekyll-redirect-from's generator still sees
# redirect_from. Clears memoized URL on the document when we override permalink.
Jekyll::Hooks.register :site, :post_read do |site|
  posts = site.collections["posts"]&.docs
  next unless posts

  posts.each do |doc|
    next unless doc.relative_path&.start_with?("_posts/podcasts/")

    data = doc.data
    perm = data["permalink"].to_s.strip
    next if !perm.empty? && !perm.match?(/:[a-z_]+/i)

    slug = data["slug"].to_s
    next unless slug.end_with?("-md")

    base = slug.delete_suffix("-md")
    next if base.empty?

    data["permalink"] = "/#{base}.html"
    data["slug"] = base

    old_path = "/#{slug}.html"
    case data["redirect_from"]
    when nil, false
      data["redirect_from"] = [old_path]
    when Array
      data["redirect_from"] = (data["redirect_from"] + [old_path]).uniq
    when String
      data["redirect_from"] = [data["redirect_from"], old_path].uniq
    end

    %i[@url @url_placeholders @destination @id @to_liquid].each do |iv|
      doc.remove_instance_variable(iv) if doc.instance_variable_defined?(iv)
    end
  end
end
