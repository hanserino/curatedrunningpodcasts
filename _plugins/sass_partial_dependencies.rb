# frozen_string_literal: true

# jekyll-sass-converter compiles Sass without wiring import graphs into Jekyll’s
# incremental regenerator. With `jekyll serve --incremental`, only `main.scss`
# mtime is considered—editing `_style/**/*.scss` left stale CSS until this hook.
Jekyll::Hooks.register :site, :pre_render do |site, _payload|
  next unless site.incremental?

  dependent = site.in_source_dir("assets/style/main.scss")
  next unless File.file?(dependent)
  next if site.regenerator.metadata[dependent].nil?

  sass_dir = site.config["sass"] && site.config["sass"]["sass_dir"]
  sass_dir = "_sass" if sass_dir.nil? || sass_dir.to_s.strip.empty?
  root = site.in_source_dir(sass_dir)
  next unless File.directory?(root)

  Dir.glob(File.join(root, "**", "*.{scss,sass}")).each do |dep|
    site.regenerator.add_dependency(dependent, dep)
  end
end
