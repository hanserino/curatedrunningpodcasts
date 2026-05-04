# Best Running Podcasts (Curated)

An independent, hand-curated directory of running podcasts (road, track, trail, ultra, and training). Each entry is a short write-up with listening links and filterable metadata.

**Live site:** [bestrunningpodcasts.com](https://bestrunningpodcasts.com)

## Stack

- **Jekyll 4** — static site; posts are Markdown in `_posts/podcasts/`.
- **SCSS** — styles under `_style/`; compiled to `docs/assets/style/`.
- **Vanilla JS** — home-page filtering and layout toggle (`assets/scripts/main.js`; wired from `_includes/footer.html`).
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

- **Styles:** entry file is `assets/style/main.scss`; partials live under `_style/` (`sass.sass_dir` in `_config.yml`). With **`--incremental`**, Jekyll normally would not recompile CSS when only a partial changes; `_plugins/sass_partial_dependencies.rb` registers those files so partial edits still refresh `main.css`. If file events are missed (some network disks or VMs), use `bundle exec jekyll serve --force-polling`.
- Default output is **`docs/`** (`destination: docs` in `_config.yml`); that folder is what GitHub Pages serves for this project.
- For production-like URLs in feeds, sitemaps, and meta tags, use:

```bash
JEKYLL_ENV=production bundle exec jekyll build
```

Commit the updated **`docs/`** tree (HTML, assets, and `admin/`) so the live site matches your source changes.

## Scheduled RSS rebuilds (GitHub Actions)

Episode lists on the site come from **`_data/latest_podcast_episodes.yml`**, which is filled when Jekyll runs with production RSS fetching. To refresh feeds without a manual build, this repo includes **`.github/workflows/scheduled-jekyll-build.yml`**, which:

- Runs **every hour** (UTC) and can be triggered manually under **Actions → Scheduled Jekyll build (RSS) → Run workflow**
- Runs `JEKYLL_ENV=production` + `JEKYLL_FETCH_RSS=1` and `jekyll build --destination docs`
- **Commits and pushes** only when `docs/` or `_data/latest_podcast_episodes.yml` actually change

**One-time GitHub setup:** open the repository **Settings → Actions → General → Workflow permissions**, choose **Read and write permissions**, and save. Without that, the workflow cannot push refreshed files to `main`.

To change how often jobs run, edit the `cron` expression in the workflow file (all times are **UTC**).

## Repository layout (short)

| Path | Role |
| --- | --- |
| `_config.yml` | Site URL, title, description, post defaults, plugins |
| `_posts/podcasts/` | Podcast entry Markdown (filename `YYYY-MM-DD-slug.md`) |
| `media/` | Artwork and uploads referenced from posts |
| `admin/` | Decap `index.html` + `config.yml` (built into `docs/admin/`) |
| `index.md`, `_layouts/`, `_includes/` | Home page, templates, header/footer/filter |
| `.github/workflows/` | CI (scheduled Jekyll / RSS refresh) |

---

Design, content, and code by [@hanserino](https://www.instagram.com/hanserino), host of [Nå Er Det Alvor (NEDA)](https://www.naerdetalvor.no/).
