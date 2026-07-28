---
layout: home
title: Plastics
---

# Plastics

Culture, meaning, ideology, and their relationship to contemporary life

[Spotify](https://open.spotify.com/show/6mFcaEBDzAQcGklB9cWJCJ?si=6d84b2ef525248f5) [YouTube](https://www.youtube.com/@plasticspod) [Apple](https://podcasts.apple.com/us/podcast/plastics/id1725599105) [RSS](https://anchor.fm/s/f0ad9940/podcast/rss)

{% for episode in site.data.plastics %}

<div class="episode">
  {% if episode.image %}
  <a class="episode__thumb" href="{{ episode.link }}">
    <img src="{{ episode.image }}" alt="" />
  </a>
  {% endif %}
  <div class="episode__body">
    <h3><a href="{{ episode.link }}">{{ episode.title }}</a></h3>
    <p class="episode__meta">{{ episode.date }} · {{ episode.duration }}</p>
    <p>{{ episode.description }}</p>
    <audio controls preload="none" src="{{ episode.audio }}"></audio>
  </div>
</div>
{% endfor %}
