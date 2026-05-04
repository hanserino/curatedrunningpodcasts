source "https://rubygems.org"

# Jekyll 4. Use jekyll-sass-converter 2.x + sassc (libsass), not dart sass-embedded.
# sass-embedded (converter 3.x) can raise "can't alloc thread" during `jekyll serve`
# watch rebuilds on macOS. sassc avoids the embedded Dart VM. Requires a one-time
# native compile of libsass. Ruby ≥ 3.1 can instead drop these two lines and use the
# default jekyll-sass-converter 3 + sass-embedded from Jekyll’s dependencies.
# Build output goes to docs/ and is served as static files on GitHub Pages.
# Production build (correct absolute URLs in meta, feed, sitemap):
#   JEKYLL_ENV=production bundle exec jekyll build
gem "jekyll", "~> 4.3"
gem "jekyll-sass-converter", "~> 2.2"
gem "sassc", "~> 2.4"
gem "webrick", "~> 1.8"
gem "kramdown-parser-gfm"
# Stdlib RSS was gemified; explicit dep so CI / bundle exec can require "rss" (_plugins/latest_podcast_episodes.rb).
gem "rss", "~> 0.3"

group :jekyll_plugins do
  gem "jekyll-feed", "~> 0.17"
  gem "jekyll-sitemap", "~> 1.4"
  gem "jekyll-redirect-from", "~> 0.16"
end

install_if -> { RUBY_PLATFORM =~ %r!mingw|mswin|java! } do
  gem "tzinfo", "~> 2.0"
  gem "tzinfo-data"
end

gem "wdm", "~> 0.1.0", :install_if => Gem.win_platform?
