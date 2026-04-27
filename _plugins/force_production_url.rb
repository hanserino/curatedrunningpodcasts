# frozen_string_literal: true

# Force public origin for `absolute_url`, jekyll-feed, and sitemap when `JEKYLL_ENV=production`.
# Some environments (and having `destination` / tooling under the repo) can make Jekyll
# leave `config["url"]` at a local dev value (e.g. http://0.0.0.0:4000) even during `jekyll build`.
PRODUCTION_URL = "https://bestrunningpodcasts.com"

Jekyll::Hooks.register :site, :post_read, priority: :high do |site|
  next unless Jekyll.env == "production"

  site.config["url"] = PRODUCTION_URL
  site.config["baseurl"] = ""
  site.filter_cache.clear if site.respond_to?(:filter_cache) && site.filter_cache
end
