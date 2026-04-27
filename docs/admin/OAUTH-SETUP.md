# Decap CMS + GitHub Pages — authentication

Decap’s **GitHub** backend needs a short **OAuth exchange**; Git does not allow putting a client *secret* in the browser, so a tiny **proxy** (Cloudflare Worker) signs users in.

Your admin UI: **`https://bestrunningpodcasts.com/admin/`**

This repo uses **[sterlingwes/decap-proxy](https://github.com/sterlingwes/decap-proxy)**. Tracked worker name: **`admin/cloudflare-decap-wrangler.toml`** (copy into the clone as `wrangler.toml`).

---

## 1. Prerequisites

- **Node.js 20+** (Wrangler 4 requires it). Check: `node -v`. On macOS with Homebrew: `brew install node@22` then ensure that `node` is on your `PATH`, or use [nvm](https://github.com/nvm-sh/nvm) / [fnm](https://github.com/Schniz/fnm).
- A **Cloudflare** account (free tier is enough).

---

## 2. Clone and deploy the worker (one-time)

From the **project root** (not inside this repo’s tracked `tools/` — that path is gitignored once you clone):

```bash
git clone --depth 1 https://github.com/sterlingwes/decap-proxy.git tools/decap-proxy
cp admin/cloudflare-decap-wrangler.toml tools/decap-proxy/wrangler.toml
cd tools/decap-proxy
npm install
npx wrangler login
npx wrangler deploy
```

`wrangler deploy` prints your worker URL, for example:

`https://curatedrunningpodcasts-decap-oauth.<your-subdomain>.workers.dev`

Open that URL in a browser — you should see **Hello 👋**.

**Keep that URL** — it is your **PROXY URL** for the next steps.

---

## 3. Register the GitHub OAuth app

[Create a GitHub OAuth App](https://github.com/settings/applications/new) (Developer settings → OAuth Apps).

Per [decap-proxy’s README](https://github.com/sterlingwes/decap-proxy), use the **proxy** host (not your public site) for both fields:

| Field | Value |
|--------|--------|
| **Homepage URL** | `https://YOUR-PROXY-HOST` (same origin as the worker, no path) |
| **Authorization callback URL** | `https://YOUR-PROXY-HOST/callback` |

Example: if the worker is `https://curatedrunningpodcasts-decap-oauth.hanserino.workers.dev`, set the callback to **`https://curatedrunningpodcasts-decap-oauth.hanserino.workers.dev/callback`**.

Save the **Client ID** and generate a **Client secret**.

---

## 4. Add secrets to the Worker

Still in `tools/decap-proxy/`:

```bash
npx wrangler secret put GITHUB_OAUTH_ID
npx wrangler secret put GITHUB_OAUTH_SECRET
```

Paste the GitHub **Client ID** and **Client secret** when prompted. Redeploy is not required for secrets.

---

## 5. Configure Decap in this repo

In **`admin/config.yml`**, under `backend:`, set (uncomment and replace the URL):

```yaml
  base_url: https://YOUR-PROXY-HOST
  auth_endpoint: /auth
```

Example:

```yaml
  base_url: https://curatedrunningpodcasts-decap-oauth.hanserino.workers.dev
  auth_endpoint: /auth
```

`repo:` and `branch:` should already match this repository.

---

## 6. Ship the site

1. Rebuild: `JEKYLL_ENV=production bundle exec jekyll build`
2. Commit **`admin/config.yml`** and **`docs/admin/config.yml`** (and other `docs/` changes from the build).
3. Push so GitHub Pages serves `/admin/` with the new config.

Only GitHub users with **write access** to **`hanserino/curatedrunningpodcasts`** can publish from the CMS.

---

## Troubleshooting

- **Login still fails** — In the OAuth app, try **adding a second** callback URL: `https://YOUR-PROXY-HOST/callback?provider=github` (the worker uses a `provider` query in the redirect URI).
- **Wrangler: Node version** — Use Node 20+.
- **Local `npx decap-server` works but production does not** — Production needs `base_url` + `auth_endpoint` and the worker secrets; see [Decap GitHub + OAuth](https://decapcms.org/docs/backends-overview/#github-backend).

## Option B — Netlify (later)

If you (later) connect the same repo to **Netlify**, you can use Netlify’s auth flow with Decap instead of this worker. See the [Decap + Netlify](https://decapcms.org/docs/authentication-backends/) docs for the `backend` block.

## Local editing (no OAuth)

Run `npx decap-server` from the project root, or set `local_backend: true` in `config.yml` **only** for local testing — do not commit that for the public site.
