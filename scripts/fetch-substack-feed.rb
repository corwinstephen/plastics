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
ARCHIVE_URL = "#{PUBLICATION}/api/v1/archive?sort=new&limit=50"
POSTS_DIR = File.expand_path("../_posts", __dir__)
USER_AGENT = "Mozilla/5.0 (compatible; plasticspod.org-substack-feed/1.3; +https://plasticspod.org)"

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
  raw = fetch("#{PUBLICATION}/api/v1/posts/#{CGI.escape(slug)}")
  data = JSON.parse(raw)
  raise "Unexpected post payload for #{slug}" unless data.is_a?(Hash)

  data
rescue RuntimeError => error
  raise unless error.message.include?("404")

  warn "Skipping missing post: #{slug}"
  nil
end

posts = []

fetch_archive.each do |entry|
  slug = entry["slug"].to_s
  slug = slug_from_link(entry["canonical_url"]) if slug.empty?
  next if slug.nil? || slug.empty?

  post = fetch_post(slug)
  next if post.nil?

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
    "body" => body
  }
end

clear_managed_posts!

posts.each do |post|
  front = {
    "layout" => "post",
    "title" => post["title"],
    "date" => post["date"],
    "source" => "substack",
    "canonical" => post["canonical"]
  }
  front["subtitle"] = post["subtitle"] if post["subtitle"]

  path = File.join(POSTS_DIR, "#{post['date']}-#{post['slug']}.html")
  write_post(path, front, post["body"])
end

puts "Wrote #{posts.length} Substack posts to #{POSTS_DIR}"
