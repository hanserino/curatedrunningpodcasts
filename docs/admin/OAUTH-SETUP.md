# Decap CMS + GitHub Pages — authentication

Decap’s **GitHub** backend needs a short **OAuth exchange**; Git does not allow putting a client *secret* in the browser, so a tiny **proxy** (or Netlify) signs users in.

Your admin UI: **`https://bestrunningpodcasts.com/admin/`** (or your GitHub Pages URL).

## Option A — Cloudflare Worker (free tier, no Netlify)

A common pattern is a small worker that implements `/auth` and `/callback` for Decap. Example template:

- [sterlingwes / decap-proxy (Cloudflare Worker)](https://github.com/sterlingwes/decap-proxy) — follow its README, set `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET`, then deploy and copy the worker URL.

Then in **`admin/config.yml`**, under `backend:`, set:

```yaml
base_url: https://YOUR-WORKER-SUBDOMAIN.workers.dev
auth_endpoint: auth
```

(If the template uses a different path, match what it documents — often `auth` and `callback` are the routes.)

**GitHub OAuth app** (Settings → Developer settings → OAuth Apps):

- **Application name:** e.g. `Best Running Podcasts Decap`
- **Homepage URL:** `https://bestrunningpodcasts.com`
- **Authorization callback URL:** the worker’s callback URL, e.g. `https://YOUR-WORKER.workers.dev/callback` (use exactly what the proxy README says)

## Option B — Netlify (if you add Netlify in front of the repo)

If you (later) build or connect the same repo to **Netlify**, you can use [Netlify’s auth provider for Git](https://docs.netlify.com/security/secure-access-to-sites/identity/setup-external-providers/) with Decap. Your site can still be served from the same `docs` build; many teams use Netlify only for the CMS login flow — check the latest Decap + Netlify docs for the exact `backend` block.

## After OAuth works

1. Commit **`admin/config.yml`** with `base_url` and `auth_endpoint` uncommented and correct.
2. Rebuild the site if `destination` is `docs` and commit **`docs/admin/`** so GitHub Pages serves `/admin/`.
3. **Collaborators** who use the CMS need **write access** to the GitHub repository (Decap uses their GitHub account to create commits).

## Local editing (no OAuth)

- Run `npx decap-server` from the project root (or follow [Decap local backend](https://decapcms.org/docs/beta-features/#local-backend)) and, when testing only, you can set `local_backend: true` in `config.yml` (do not leave it on in production for the public site, or the admin may try to use the local server for everyone).

## Removing the old `prose:` block

The **`prose:`** section in `_config.yml` was only for Prose.io; it is safe to remove (already removed). Jekyll ignores it for builds.
