# frozen_string_literal: true

# Decap uses `url_slug` in front matter (field name `slug` conflicts with Decap's built-in {{slug}} tag).
# Maps url_slug → Jekyll's `slug` for /:slug/ permalinks and episode page generation.

Jekyll::Hooks.register :site, :post_read do |site|
  posts = site.collections["posts"]&.docs
  next unless posts

  posts.each do |doc|
    next unless doc.relative_path&.start_with?("_posts/podcasts/")
    next unless doc.data["category"] == "podcast"

    url_slug = doc.data["url_slug"].to_s.strip
    if url_slug.empty?
      inferred = doc.data["slug"].to_s.strip
      if inferred.empty?
        base = File.basename(doc.relative_path, ".md")
        inferred = base.sub(/\A\d{4}-\d{2}-\d{2}-/, "")
      end
      inferred = inferred.delete_suffix("-md") if inferred.end_with?("-md")
      url_slug = inferred
      doc.data["url_slug"] = url_slug unless url_slug.empty?
    end

    next if url_slug.empty?

    doc.data["slug"] = url_slug

    %i[@url @url_placeholders @destination @id @to_liquid].each do |iv|
      doc.remove_instance_variable(iv) if doc.instance_variable_defined?(iv)
    end
  end
end
