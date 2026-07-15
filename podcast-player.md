---
layout: latest
title: Unrelated to running
permalink: /unrelated/
sitemap: false
noindex: true
description: >-
  A feed of latest episodes from podcasts unrelated to running, recommended by the runners featured on the Runner's picks page.
seo_description: >-
  Latest episodes from podcasts unrelated to running, recommended by runners from the Runner's picks page.
---

<!-- markdownlint-disable MD033 -->

{%- assign _unrelated_feed = site.data.latest_podcast_episodes.non_running_items | default: empty -%}
<div class="latest-page__controls">
  {% include filter.html show_grid=false title="Filter episodes" noun="episode" filter_page="unrelated" filter_item=".latest-episodes__item" total_count=_unrelated_feed.size show_opml_favorites=false show_favorites_filter=false show_category_filters=false %}
</div>

{% include latest-episodes-player.html items=_unrelated_feed section_id="unrelated-episodes-page" heading="Latest unrelated episodes" limit=100 %}
