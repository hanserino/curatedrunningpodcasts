# frozen_string_literal: true

# jekyll-sass-converter only keys off assets/style/main.scss. Edits under
# _style/**/*.scss do not invalidate the compiled CSS unless those partials are
# registered as regenerator dependencies of main.scss.
module SassPartialDependencies
  module_function

  def main_scss(site)
    site.in_source_dir("assets/style/main.scss")
  end

  def partial_glob(site)
    sass_dir = site.config["sass"] && site.config["sass"]["sass_dir"]
    sass_dir = "_style" if sass_dir.nil? || sass_dir.to_s.strip.empty?
    root = site.in_source_dir(sass_dir)
    return [] unless File.directory?(root)

    Dir.glob(File.join(root, "**", "*.{scss,sass}"))
  end

  def register!(site)
    dependent = main_scss(site)
    return unless File.file?(dependent)

    partial_glob(site).each do |dep|
      site.regenerator.add_dependency(dependent, dep)
    end
  end
end

Jekyll::Hooks.register :site, :pre_render do |site, _payload|
  SassPartialDependencies.register!(site)
end
