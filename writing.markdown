---
layout: home
title: Writing
permalink: /writing/
---

# Writing

Essays and notes, mirrored from [Substack](https://plasticspod.substack.com/).

{% if site.posts.size == 0 %}
<p class="post-list__empty">No posts yet.</p>
{% else %}
<ul class="post-list">
  {% for post in site.posts %}
  <li class="post-list__item">
    <a href="{{ post.url | relative_url }}">{{ post.title }}</a>
    <span class="post-list__meta">{{ post.date | date: site.theme_config.date_format }}</span>
    {% if post.subtitle %}
    <p class="post-list__subtitle">{{ post.subtitle }}</p>
    {% endif %}
  </li>
  {% endfor %}
</ul>
{% endif %}
