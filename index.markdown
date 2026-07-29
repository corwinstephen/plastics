---
layout: home
title: "Plastics ♹"
---

# Plastics ♹

Culture, meaning, ideology, complexity.

[Spotify](https://open.spotify.com/show/6mFcaEBDzAQcGklB9cWJCJ?si=6d84b2ef525248f5) [YouTube](https://www.youtube.com/@plasticspod) [Apple](https://podcasts.apple.com/us/podcast/plastics/id1725599105) [RSS](https://anchor.fm/s/f0ad9940/podcast/rss)

{% assign feed_keys = "" | split: "" %}

{% for post in site.posts %}
  {% capture key %}{{ post.date | date: "%Y-%m-%d" }}#post#{{ post.url }}{% endcapture %}
  {% assign feed_keys = feed_keys | push: key %}
{% endfor %}

{% for episode in site.data.plastics %}
  {% capture key %}{{ episode.date }}#episode#{{ forloop.index0 }}{% endcapture %}
  {% assign feed_keys = feed_keys | push: key %}
{% endfor %}

{% assign feed_keys = feed_keys | sort | reverse %}

{% for key in feed_keys %}
  {% assign parts = key | split: "#" %}
  {% assign kind = parts[1] %}

  {% if kind == "post" %}
    {% assign post_url = parts[2] %}
    {% for post in site.posts %}
      {% if post.url == post_url %}
<div class="entry entry--post">
  <div class="entry__body">
    <h3><a href="{{ post.url | relative_url }}">{{ post.title }}</a></h3>
    <p class="entry__meta">{{ post.date | date: site.theme_config.date_format }} · Writing</p>
    {% if post.subtitle %}
    <p>{{ post.subtitle }}</p>
    {% endif %}
  </div>
</div>
      {% endif %}
    {% endfor %}
  {% else %}
    {% assign episode_index = parts[2] | plus: 0 %}
    {% assign episode = site.data.plastics[episode_index] %}
<div class="entry entry--episode">
  {% if episode.image %}
  <a class="entry__thumb" href="{{ episode.link }}">
    <img src="{{ episode.image }}" alt="" width="112" height="112" />
  </a>
  {% endif %}
  <div class="entry__body">
    <h3><a href="{{ episode.link }}">{{ episode.title }}</a></h3>
    <p class="entry__meta">{{ episode.date }} · {{ episode.duration }}</p>
    <p>{{ episode.description }}</p>
    <audio controls preload="none" src="{{ episode.audio }}"></audio>
  </div>
</div>
  {% endif %}
{% endfor %}
