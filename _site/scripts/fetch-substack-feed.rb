#!/usr/bin/env ruby
# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "cgi"
require "fileutils"
require "json"
require "net/http"
require "time"
require "yaml"

PUBLICATION = "https://plasticspod.substack.com"
AUTHOR_HANDLE = "plasticspod"
ARCHIVE_URL = "#{PUBLICATION}/api/v1/archive?sort=new&limit=50"
NOTES_URL = "#{PUBLICATION}/api/v1/notes"
POSTS_DIR = File.expand_path("../_posts", __dir__)
USER_AGENT = "Mozilla/5.0 (compatible; plasticspod.org-substack-feed/1.2; +https://plasticspod.org)"
NOTES_PAGE_LIMIT = 5

def fetch(url, limit = 5)
  raise "Too many redirects" if limit <= 0

  body, code = http_get(url)
  return body if code >= 200 && code < 300

  if [403, 429, 503].include?(code)
    warn "Direct fetch returned #{code} for #{url}; retrying via Jina proxy"
    proxy_url = "https://r.jina.ai/#{url}"
    body, proxy_code = http_get(proxy_url, "X-Return-Format" => "text")
    return body if proxy_code >= 200 && proxy_code < 300

    raise "Failed to fetch via proxy: #{proxy_code}"
  end

  if code >= 300 && code < 400
    location = @last_location
    raise "Redirect without Location for #{url}" if location.nil? || location.empty?

    return fetch(location, limit - 1)
  end

  raise "Failed to fetch #{url}: #{code}"
end

def http_get(url, extra_headers = {})
  uri = URI(url)
  request = Net::HTTP::Get.new(uri)
  request["User-Agent"] = USER_AGENT
  request["Accept"] = "application/json, application/xml, text/xml, text/plain, */*"
  request["Accept-Language"] = "en-US,en;q=0.9"
  extra_headers.each { |key, value| request[key] = value }

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 30, read_timeout: 60) do |http|
    http.request(request)
  end

  @last_location = response["location"]
  [response.body.to_s, response.code.to_i]
end

def slug_from_link(link)
  return nil if link.nil? || link.empty?

  path = URI(link).path.to_s
  slug = path.split("/").reject(&:empty?).last
  return nil if slug.nil? || slug.empty?

  CGI.unescape(slug).downcase.gsub(/[^a-z0-9\-]+/, "-").gsub(/\A-+|-+\z/, "")
end

def managed_substack_post?(path)
  content = File.read(path, encoding: "UTF-8")
  return false unless content.valid_encoding? ? content =~ /\A---\s*\n(.*?)\n---/m : false

  front = YAML.safe_load(Regexp.last_match(1))
  front.is_a?(Hash) && front["source"] == "substack"
rescue Psych::SyntaxError, ArgumentError
  false
end

def clear_managed_posts!
  FileUtils.mkdir_p(POSTS_DIR)
  Dir.glob(File.join(POSTS_DIR, "*.{md,markdown,html}")).each do |path|
    File.delete(path) if managed_substack_post?(path)
  end
end

def write_post(path, front, body)
  File.write(path, "#{front.to_yaml}---\n\n#{body.strip}\n")
end

def fetch_archive
  data = JSON.parse(fetch(ARCHIVE_URL))
  raise "Unexpected archive payload" unless data.is_a?(Array)

  data
end

def fetch_post(slug)
  data = JSON.parse(fetch("#{PUBLICATION}/api/v1/posts/#{CGI.escape(slug)}"))
  raise "Unexpected post payload for #{slug}" unless data.is_a?(Hash)

  data
end

def fetch_notes
  notes = []
  cursor = nil

  NOTES_PAGE_LIMIT.times do
    url = "#{NOTES_URL}?limit=50"
    url += "&cursor=#{CGI.escape(cursor)}" if cursor

    data = JSON.parse(fetch(url))
    raise "Unexpected notes payload" unless data.is_a?(Hash)

    items = data["items"]
    break unless items.is_a?(Array) && !items.empty?

    items.each do |item|
      note = note_from_item(item)
      notes << note if note
    end

    cursor = data["nextCursor"]
    break if cursor.nil? || cursor.to_s.empty?
  end

  notes
end

def note_from_item(item)
  return nil unless item.is_a?(Hash)
  return nil unless item.dig("context", "type") == "note"

  comment = item["comment"]
  return nil unless comment.is_a?(Hash)
  return nil unless comment["handle"].to_s == AUTHOR_HANDLE
  return nil if restack_note?(item, comment)

  note_id = comment["id"]
  return nil if note_id.nil?

  body_html = note_body_html(comment)
  return nil if body_html.strip.empty?

  date_raw = comment["date"] || item.dig("context", "timestamp")
  return nil if date_raw.nil? || date_raw.to_s.empty?

  date = Time.parse(date_raw.to_s).strftime("%Y-%m-%d")
  title = note_title(comment)
  slug = "note-c-#{note_id}"
  canonical = "https://substack.com/@#{AUTHOR_HANDLE}/note/c-#{note_id}"

  {
    "slug" => slug,
    "title" => title,
    "date" => date,
    "canonical" => canonical,
    "kind" => "note",
    "body" => body_html
  }
end

def restack_note?(item, comment)
  context_type = item.dig("context", "type").to_s
  return true if context_type.end_with?("_restack")
  return true if comment["restacked"] == true

  attachments = Array(comment["attachments"])
  attachments.any? { |attachment| %w[post comment].include?(attachment["type"].to_s) }
end

def note_title(comment)
  body = comment["body"].to_s.gsub(/\s+/, " ").strip
  return truncate(body, 80) unless body.empty?

  (comment["attachments"] || []).each do |attachment|
    case attachment["type"]
    when "post"
      post_title = attachment.dig("post", "title").to_s.strip
      return "Re: #{post_title}" unless post_title.empty?
    when "image"
      return "Note"
    when "comment"
      quoted = attachment.dig("comment", "body").to_s.gsub(/\s+/, " ").strip
      return truncate(quoted, 80) unless quoted.empty?
    end
  end

  "Note"
end

def truncate(text, max)
  return text if text.length <= max

  "#{text[0, max - 1].sub(/\s+\S*\z/, '').rstrip}…"
end

def note_body_html(comment)
  parts = []

  json_html = render_body_json(comment["body_json"])
  if json_html && !json_html.strip.empty?
    parts << json_html
  else
    plain = comment["body"].to_s.strip
    unless plain.empty?
      paragraphs = plain.split(/\n{2,}/).map do |paragraph|
        "<p>#{CGI.escapeHTML(paragraph).gsub("\n", "<br>")}</p>"
      end
      parts.concat(paragraphs)
    end
  end

  (comment["attachments"] || []).each do |attachment|
    html = render_attachment(attachment)
    parts << html if html && !html.empty?
  end

  parts.join("\n")
end

def render_body_json(node)
  return "" unless node.is_a?(Hash)

  case node["type"]
  when "doc"
    Array(node["content"]).map { |child| render_body_json(child) }.join
  when "paragraph"
    inner = Array(node["content"]).map { |child| render_body_json(child) }.join
    "<p>#{inner}</p>"
  when "text"
    text = CGI.escapeHTML(node["text"].to_s)
    Array(node["marks"]).each do |mark|
      next unless mark.is_a?(Hash)

      case mark["type"]
      when "bold"
        text = "<strong>#{text}</strong>"
      when "italic"
        text = "<em>#{text}</em>"
      when "link"
        href = CGI.escapeHTML(mark.dig("attrs", "href").to_s)
        text = %(<a href="#{href}">#{text}</a>) unless href.empty?
      end
    end
    text
  else
    Array(node["content"]).map { |child| render_body_json(child) }.join
  end
end

def render_attachment(attachment)
  return "" unless attachment.is_a?(Hash)

  case attachment["type"]
  when "image"
    src = attachment["imageUrl"].to_s
    return "" if src.empty?

    %(<p><img src="#{CGI.escapeHTML(src)}" alt=""></p>)
  when "post"
    post = attachment["post"] || {}
    title = post["title"].to_s.strip
    url = post["canonical_url"].to_s.strip
    subtitle = post["subtitle"].to_s.strip
    return "" if url.empty?

    label = title.empty? ? url : title
    html = %(<p><a href="#{CGI.escapeHTML(url)}">#{CGI.escapeHTML(label)}</a></p>)
    html += "<p>#{CGI.escapeHTML(subtitle)}</p>" unless subtitle.empty?
    html
  when "comment"
    quoted = attachment.dig("comment", "body").to_s.strip
    return "" if quoted.empty?

    %(<blockquote><p>#{CGI.escapeHTML(quoted).gsub("\n", "<br>")}</p></blockquote>)
  else
    ""
  end
end

def collect_newsletter_posts
  posts = []

  fetch_archive.each do |entry|
    slug = entry["slug"].to_s
    slug = slug_from_link(entry["canonical_url"]) if slug.empty?
    next if slug.nil? || slug.empty?

    post = fetch_post(slug)
    title = post["title"].to_s.strip
    next if title.empty?

    body = post["body_html"].to_s.strip
    next if body.empty?

    post_date = post["post_date"] || entry["post_date"]
    next if post_date.nil? || post_date.to_s.empty?

    date = Time.parse(post_date.to_s).strftime("%Y-%m-%d")
    canonical = post["canonical_url"] || entry["canonical_url"] || "#{PUBLICATION}/p/#{slug}"
    subtitle = post["subtitle"].to_s.strip
    subtitle = nil if subtitle.empty?

    posts << {
      "slug" => slug,
      "title" => title,
      "date" => date,
      "canonical" => canonical,
      "subtitle" => subtitle,
      "kind" => "post",
      "body" => body
    }
  end

  posts
end

posts = collect_newsletter_posts + fetch_notes

clear_managed_posts!

posts.each do |post|
  front = {
    "layout" => "post",
    "title" => post["title"],
    "date" => post["date"],
    "source" => "substack",
    "kind" => post["kind"],
    "canonical" => post["canonical"]
  }
  front["subtitle"] = post["subtitle"] if post["subtitle"]

  path = File.join(POSTS_DIR, "#{post['date']}-#{post['slug']}.html")
  write_post(path, front, post["body"])
end

note_count = posts.count { |post| post["kind"] == "note" }
post_count = posts.length - note_count
puts "Wrote #{post_count} posts and #{note_count} notes to #{POSTS_DIR}"
