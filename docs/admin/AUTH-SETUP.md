# Google sign-in + cross-device sync (Supabase)

This site can sync **listen progress**, **continue listening**, and **OPML favorites** across devices when a visitor signs in with Google.

The static site stays on GitHub Pages. Supabase handles auth and per-user storage.

---

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com/) and create a project.
2. In **Project Settings → API**, copy:
   - **Project URL**
   - **anon public** key (safe to use in the browser)

---

## 2. Create the database table

In **SQL Editor**, run the SQL from:

`supabase/schema.sql`

This creates `public.user_library` with row-level security so each user can only read/write their own row.

---

## 3. Enable Google sign-in

1. In Supabase: **Authentication → Providers → Google** → enable.
2. Create a [Google Cloud OAuth client](https://console.cloud.google.com/apis/credentials) (Web application).
3. Add **Authorized redirect URIs** from Supabase (shown on the Google provider page), typically:
   - `https://<project-ref>.supabase.co/auth/v1/callback`
4. Paste Google **Client ID** and **Client secret** into Supabase.

In **Authentication → URL configuration**:

**Site URL** (one value only — use production):

- `https://bestrunningpodcasts.com`

**Redirect URLs** (add multiple; wildcards are fine):

- `https://bestrunningpodcasts.com/**`
- `http://127.0.0.1:4000/**`

Local dev does **not** go in Site URL. Add `http://127.0.0.1:4000/**` under Redirect URLs so Google sign-in works when you test with `jekyll serve`.

---

## 4. Configure the Jekyll site

In `_config.yml`:

```yaml
supabase:
  url: "https://YOUR-PROJECT.supabase.co"
  anon_key: "YOUR-ANON-KEY"
```

Paste only the JWT from **anon public** (starts with `eyJ...`). Do not include the label `Anon public:` — that breaks YAML and sign-in.

Leave both empty to hide sign-in (local-only mode).

Rebuild or restart `jekyll serve` after changing `_config.yml`.

---

## 5. What gets synced

| Local storage key | Synced field |
|-------------------|--------------|
| `brp-listen-progress-v1` | `listen_progress` |
| `brp-last-listened-v1` | `last_listened` |
| `brp-opml-favorites` | `favorites` |
| `brp-filter-prefs-v1` | `filter_prefs` |

`filter_prefs` stores separate home-directory and latest-episodes filter choices (categories, language, and grid layout on the home page). Keys: `home` and `latest`.

On sign-in, local and cloud data are **merged** (newer timestamps win for progress and per-page filters; favorites are unioned). While signed in, changes debounce to the cloud every ~2 seconds.

**Existing Supabase projects:** if `user_library` was created before filter sync, run the `alter table ... add column if not exists filter_prefs` statement at the bottom of `supabase/schema.sql`.

---

## 6. Google OAuth verification

Google's OAuth consent screen asks for an **application home page** on your domain. That URL does **not** have to be the site root.

Use this dedicated page (same styling as Privacy/Terms):

- **Application home page:** `https://bestrunningpodcasts.com/app/`
- **Privacy policy:** `https://bestrunningpodcasts.com/privacy/`
- **Terms of service:** `https://bestrunningpodcasts.com/terms/`

In [Google Cloud Console → OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent), set **Application home page** to `/app/`, not `/`. The public podcast directory at `/` stays unchanged.

If verification still stalls, reply to Google's email confirming the homepage URL was updated.

**Testing mode:** While the app is in *Testing*, only users you add as test users can sign in — and full brand verification is not required. Switch to *Production* only when you need public Google sign-in.

---

## 7. Privacy

A public privacy page is published at **`/privacy/`** (`privacy.md`). It covers:

- optional Google sign-in via Supabase
- what is stored (episode URLs, listen progress, favorites)
- Google Analytics
- how visitors can sign out or request deletion

**Operator: deleting a user manually**

1. In Supabase **Table Editor**, delete the row in `user_library` for that user.
2. In **Authentication → Users**, delete the auth user.

For deletion requests from visitors, use the contact email on the privacy page.
