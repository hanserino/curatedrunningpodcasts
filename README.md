# Best Running Podcasts (Curated)

An independent, hand-curated directory of running podcasts (road, track, trail, ultra, and training). Each entry is a short write-up with listening links and filterable metadata.

**Live site:** [bestrunningpodcasts.com](https://bestrunningpodcasts.com)

## Stack

- **Jekyll 4** — static site; posts are Markdown in `_posts/podcasts/`.
- **SCSS** — styles under `_style/`; compiled to `docs/assets/style/`.
- **jQuery** — home-page filtering (see `_includes/filter.html` and `assets/scripts/main.js`).
- **Plugins** — [jekyll-feed](https://github.com/jekyll/jekyll-feed) (RSS) and [jekyll-sitemap](https://github.com/jekyll/jekyll-sitemap).

Site metadata, SEO, and structured data are centralized in `_config.yml` and `head` / `schema` includes. There is a [`llms.txt`](https://bestrunningpodcasts.com/llms.txt) for tools and assistants.

## Editing content

- **In the browser:** open **`/admin/`** on the deployed site and sign in with GitHub. The public footer also has an **Admin** link. Content is managed with [Decap CMS](https://decapcms.org/); the config lives in `admin/config.yml` (also copied to `docs/admin/` on build). Publishing creates or updates files under `_posts/podcasts/` and `media/`.
- **On GitHub Pages**, Decap needs a [GitHub OAuth app + proxy](https://decapcms.org/docs/authentication-backends/); this repo’s steps are in **`admin/OAUTH-SETUP.md`**. Only people with **write access** to the repository can actually publish; others may still be able to open the admin UI.
- **Locally** you can use `npx decap-server` (see `admin/config.yml` comments) or edit Markdown and images by hand, then run a build (below).

## Building and previewing

```bash
bundle install
bundle exec jekyll serve
```

- Default output is **`docs/`** (`destination: docs` in `_config.yml`); that folder is what GitHub Pages serves for this project.
- For production-like URLs in feeds, sitemaps, and meta tags, use:

```bash
JEKYLL_ENV=production bundle exec jekyll build
```

Commit the updated **`docs/`** tree (HTML, assets, and `admin/`) so the live site matches your source changes.

## Repository layout (short)

| Path | Role |
| --- | --- |
| `_config.yml` | Site URL, title, description, post defaults, plugins |
| `_posts/podcasts/` | Podcast entry Markdown (filename `YYYY-MM-DD-slug.md`) |
| `media/` | Artwork and uploads referenced from posts |
| `admin/` | Decap `index.html` + `config.yml` (built into `docs/admin/`) |
| `index.md`, `_layouts/`, `_includes/` | Home page, templates, header/footer/filter |

---

Design, content, and code by [@hanserino](https://www.instagram.com/hanserino), host of [Nå Er Det Alvor (NEDA)](https://www.naerdetalvor.no/).
