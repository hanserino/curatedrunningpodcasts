---
layout: privacy
title: Privacy Policy
kicker: Your data on this site
permalink: /privacy/
description: >-
  How this site handles analytics, optional Google sign-in, and synced listening data.
seo_description: >-
  How Best Running Podcasts handles analytics, optional Google sign-in, and synced listening data.
---

**Best Running Podcasts** is published by **[NEDA](https://www.naerdetalvor.no/)**. This privacy policy explains what data the site uses, including optional Google sign-in, and how you can control it.

Last updated: July 2026.

## Using the site without signing in

You can browse and listen without an account. In that case, the site may store some preferences **only in your browser** using `localStorage`, for example:

- episode listen progress
- your “continue listening” episode
- starred podcasts for OPML export

That data stays on your device unless you clear site data in your browser. We do not receive it unless you choose to sign in (see below).

## Optional Google sign-in

You can optionally **Sign in with Google** to sync favorites and listening progress across devices.

Sign-in is handled by **[Supabase](https://supabase.com/)** using Google OAuth. We do not see or store your Google password. After sign-in, Supabase gives us a user ID and, typically, your Google account email address for display in the header.

When you are signed in, we store the following in your Supabase `user_library` row:

- **Listen progress** — episode audio URLs with playback position, played status, and timestamps
- **Continue listening** — the last episode you were playing, with title and cover metadata
- **Play queue** — episodes in Up next, including manual queue order and dismissed suggestions
- **Episode metadata** — titles, podcast names, cover art, and page URLs for queued and played episodes
- **Favorites** — podcast page URLs you have starred for OPML export
- **Filter preferences** — your home and latest-episodes filter choices

We use this data only to restore your experience on other browsers or devices. We do not sell it or use it for advertising profiles.

On sign-in, data already on your device is **merged** with your cloud library (newer progress and metadata win; play queues combine; favorites are combined). While signed in, changes sync to the cloud periodically.

You can **Sign out** at any time from the header. Signing out stops further cloud sync; data already in the cloud remains until you ask us to delete it.

## Analytics {#analytics}

The site can use **Google Analytics** to understand aggregate traffic, such as page views and referrers. Analytics is **optional**: we only load Google Analytics after you choose **Accept analytics** in the cookie banner. If you decline, analytics scripts are not loaded.

When enabled, Google may set cookies or similar identifiers according to [Google’s privacy policy](https://policies.google.com/privacy). We ask Google Analytics to use IP anonymization.

You can change your choice at any time using the button below, by clearing site data for this domain in your browser, or with a tracker blocker.

<button type="button" class="privacy-prose__consent-reopen" data-analytics-consent-reopen>Change analytics choice</button>

## Third-party services

Depending on how you use the site, data may be processed by:

| Service | Purpose |
| ------- | ------- |
| **Google** | Optional sign-in (OAuth) and site analytics |
| **Supabase** | Authentication and synced library storage for signed-in users |
| **GitHub Pages** | Hosting the static website |
| **Podcast hosts** | When you play an episode, your browser requests audio directly from the podcast’s feed host |

This directory also links to external podcast apps (Spotify, Apple Podcasts, etc.). Those services have their own privacy policies.

## Your choices

- **Stay signed out** — everything works with browser-only storage.
- **Sign out** — use the header button; cloud sync stops.
- **Clear local data** — remove site data / local storage for this domain in your browser settings.
- **Delete cloud data** — email us (see below) from the Google account you used to sign in. We will delete your `user_library` row and Supabase auth user.

## Contact

Questions or deletion requests:

- **[alvorpodcast@gmail.com](mailto:alvorpodcast@gmail.com)**
- Site operator: **[Hans Kristian Smedsrød Engdahl](https://www.instagram.com/hanserino/)** · [NEDA](https://www.naerdetalvor.no/)

If you are in the EU/EEA, you may have rights to access, correct, or delete personal data we hold about you. Contact us using the email above and we will respond as soon as we reasonably can.
