---
layout: latest
title: Latest Podcast Episodes
description: >-
  The newest episode from each curated show in the directory.
permalink: /latest-episodes/
---

{%- assign _latest_feed = site.data.latest_podcast_episodes.items | default: empty -%}
<div class="latest-page__controls">
  {% include filter.html show_grid=false title="Filter episodes" noun="episode" filter_item=".latest-episodes__item" total_count=_latest_feed.size show_opml_favorites=false show_favorites_filter=true %}
</div>

{% include latest-episodes-player.html section_id="latest-episodes-page" heading="Latest episodes across all shows" limit=100 %}
