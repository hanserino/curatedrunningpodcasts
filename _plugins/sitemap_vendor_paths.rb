# frozen_string_literal: true

# Read jekyll-sitemap Liquid templates from ./_jekyll-sitemap/ when present, falling
# back to the gem. Fixes "No such file @ rb_sysopen ... jekyll-sitemap-.../lib/sitemap.xml"
# when the gem package in Bundler cache is incomplete (e.g. Cursor sandbox).

module Jekyll
  module SitemapVendorPaths
    def source_path(file = "sitemap.xml")
      vendored = File.expand_path(File.join(@site.source, "_jekyll-sitemap", file))
      return vendored if File.file?(vendored)

      super
    end
  end
end

Jekyll::Hooks.register :site, :after_init do
  unless defined?(Jekyll::JekyllSitemap)
    Jekyll.logger.warn "SitemapVendorPaths:", "jekyll-sitemap gem not loaded; skipping vendor path patch."
    next
  end

  unless Jekyll::JekyllSitemap.ancestors.include?(Jekyll::SitemapVendorPaths)
    Jekyll::JekyllSitemap.prepend(Jekyll::SitemapVendorPaths)
  end
end
