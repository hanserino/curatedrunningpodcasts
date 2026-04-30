"""
Legacy helper for rewriting a prebuilt `docs/` tree (static export only).

Production GitHub Pages builds with Jekyll from source: canonical podcast URLs are
`/<slug>.html` at the site root, with `redirect_from` in each post for older
`/podcast/...` paths. Prefer `bundle exec jekyll build` over this script.

When run, it assumes older paths under `/podcast/YYYY/MM/DD/...` and flat
`/podcast/<slug>.html`, and can copy HTML into new locations for a static host.
"""

from __future__ import annotations

import argparse
import pathlib
import re


def clean_slug_base(old_slug: str) -> str:
    # Decap filenames often end with "-md" (from "widget: image" slug naming).
    return re.sub(r"-md\Z", "", old_slug)


REDIRECT_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Redirecting…</title>
  <meta name="robots" content="noindex, follow" />
  <meta http-equiv="refresh" content="0; url={new_url_rel}" />
  <link rel="canonical" href="{new_url_rel}" />
</head>
<body>
  Redirecting to <a href="{new_url_rel}">{new_url_rel}</a>…
  <script>window.location.replace({new_url_rel!r});</script>
</body>
</html>
"""

def parse_site_url() -> str:
    # `_config.yml` contains `url: 'https://bestrunningpodcasts.com'`.
    import re

    text = pathlib.Path("_config.yml").read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"^url:\s*['\"]?(https?://[^'\"\s]+)", text, flags=re.M)
    if not m:
        raise SystemExit("Could not parse site `url` from _config.yml")
    return m[1]


def extract_post_date_and_raw_slug(stem: str) -> tuple[str, str]:
    # stem: 2026-04-28-inside-running-podcast-md
    # returns: ("2026-04-28", "inside-running-podcast-md")
    import re

    m = re.match(r"^(\d{4}-\d{2}-\d{2})-(.+)$", stem)
    if not m:
        raise ValueError(f"Unexpected post filename stem: {stem}")
    return m[1], m[2]


def file_date_parts(date_prefix: str) -> tuple[str, str, str]:
    # YYYY-MM-DD -> (YYYY, MM, DD)
    y, m, d = date_prefix.split("-")
    return y, m, d


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--docs-dir", default="docs")
    args = ap.parse_args()

    docs_dir = pathlib.Path(args.docs_dir)
    site_url = parse_site_url().rstrip("/")
    podcast_root = docs_dir / "podcast"
    if not podcast_root.exists():
        raise SystemExit(f"Missing directory: {podcast_root}")

    # Detect slug collisions after cleaning "-md".
    # If duplicates exist, we append the original date to keep the URL unique.
    source_posts_dir = pathlib.Path("_posts/podcasts")
    duplicate_bases: set[str] = set()
    if source_posts_dir.exists():
        counts: dict[str, int] = {}
        for md in source_posts_dir.glob("*.md"):
            date_prefix, raw_slug = extract_post_date_and_raw_slug(md.stem)
            cleaned = clean_slug_base(raw_slug)
            if not cleaned:
                continue
            counts[cleaned] = counts.get(cleaned, 0) + 1
        duplicate_bases = {k for k, v in counts.items() if v > 1}

    # Build a mapping from existing old rendered pages to new clean pages.
    # We iterate the actual docs output so we always use the correct date folders.
    old_to_new: list[tuple[str, str]] = []  # (old_url_abs, new_url_abs)

    for old_html_path in podcast_root.glob("*/*/*/*.html"):
        old_slug = old_html_path.stem  # filename without .html

        # docs/podcast/<YYYY>/<MM>/<DD>/<slug>.html
        y = old_html_path.parent.parent.parent.name
        mo = old_html_path.parent.parent.name
        d = old_html_path.parent.name

        clean_base = clean_slug_base(old_slug)
        if not clean_base:
            continue

        if clean_base in duplicate_bases:
            new_slug = f"{clean_base}-{y}-{mo}-{d}"
        else:
            new_slug = clean_base

        old_url_abs = f"{site_url}/podcast/{y}/{mo}/{d}/{old_slug}.html"
        new_url_abs = f"{site_url}/{new_slug}.html"

        new_html_path = docs_dir / f"{new_slug}.html"
        new_html_path.parent.mkdir(parents=True, exist_ok=True)

        # Copy old content into new clean page and rewrite URL strings inside it.
        old_content = old_html_path.read_text(encoding="utf-8", errors="ignore")
        new_content = old_content.replace(old_url_abs, new_url_abs)
        new_content = new_content.replace(old_url_abs.rstrip("/"), new_url_abs.rstrip("/"))
        new_html_path.write_text(new_content, encoding="utf-8")

        # Overwrite old date-based pages with redirect stubs.
        new_url_rel = new_url_abs.replace(f"{site_url}/", "/")
        old_html_path.write_text(
            REDIRECT_TEMPLATE.format(new_url_rel=new_url_rel),
            encoding="utf-8",
        )

        old_to_new.append((old_url_abs, new_url_abs))

    if not old_to_new:
        raise SystemExit("No old podcast pages found under docs/podcast/*/*/*/*.html")

    # 3) Update the home page, sitemap, and feed to reference the new clean URLs.
    index_html = docs_dir / "index.html"
    sitemap_xml = docs_dir / "sitemap.xml"
    feed_xml = docs_dir / "feed.xml"

    def replace_in_file(path: pathlib.Path) -> None:
        if not path.exists():
            return
        text = path.read_text(encoding="utf-8", errors="ignore")
        for old_url_abs, new_url_abs in old_to_new:
            text = text.replace(old_url_abs, new_url_abs)
        path.write_text(text, encoding="utf-8")

    replace_in_file(index_html)
    replace_in_file(sitemap_xml)
    replace_in_file(feed_xml)


if __name__ == "__main__":
    main()
