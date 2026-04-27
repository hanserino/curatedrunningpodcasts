source "https://rubygems.org"

# Jekyll 4 with Dart Sass (via jekyll-sass-converter 3.x / sass-embedded).
# Build output goes to docs/ and is served as static files on GitHub Pages.
# Production build (correct absolute URLs in meta, feed, sitemap):
#   JEKYLL_ENV=production bundle exec jekyll build
gem "jekyll", "~> 4.3"
gem "webrick", "~> 1.8"
gem "kramdown-parser-gfm"

group :jekyll_plugins do
  gem "jekyll-feed", "~> 0.17"
  gem "jekyll-sitemap", "~> 1.4"
end

install_if -> { RUBY_PLATFORM =~ %r!mingw|mswin|java! } do
  gem "tzinfo", "~> 2.0"
  gem "tzinfo-data"
end

gem "wdm", "~> 0.1.0", :install_if => Gem.win_platform?
