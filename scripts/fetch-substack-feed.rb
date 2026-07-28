#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "fileutils"
require "net/http"
require "rexml/document"
require "time"
require "yaml"

FEED_URL = "https://plasticspod.substack.com/feed"
POSTS_DIR = File.expand_path("../_posts", __dir__)

def fetch(url, limit = 5)
  raise "Too many redirects" if limit <= 0

  uri = URI(url)
  request = Net::HTTP::Get.new(uri)
  request["User-Agent"] = "plasticspod.org-substack-feed/1.0"
  request["Accept"] = "application/rss+xml, application/xml, text/xml, */*"

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(request)
  end

  case response
  when Net::HTTPSuccess
    response.body
  when Net::HTTPRedirection
    fetch(response["location"], limit - 1)
  else
    raise "Failed to fetch feed: #{response.code} #{response.message}"
  end
end

def child_text(item, local_name)
  item.elements.each do |el|
    next unless el.name == local_name

    text = element_text(el)
    return text unless text.nil? || text.empty?
  end
  nil
end

def element_text(el)
  parts = []
  el.each_child do |child|
    case child
    when REXML::CData, REXML::Text
      parts << child.to_s
    end
  end
  parts.join.strip
end

def plain_text(html)
  text = html.to_s
  text = text.gsub(/<[^>]+>/, " ")
  text = CGI.unescapeHTML(text)
  text.gsub(/\s+/, " ").strip
end

def slug_from_link(link)
  return nil if link.nil? || link.empty?

  path = URI(link).path.to_s
  slug = path.split("/").reject(&:empty?).last
  return nil if slug.nil? || slug.empty?

  CGI.unescape(slug).downcase.gsub(/[^a-z0-9\-]+/, "-").gsub(/\A-+|-+\z/, "")
end

def managed_substack_post?(path)
  content = File.read(path)
  return false unless content =~ /\A---\s*\n(.*?)\n---/m

  front = YAML.safe_load(Regexp.last_match(1))
  front.is_a?(Hash) && front["source"] == "substack"
rescue Psych::SyntaxError
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

xml = fetch(FEED_URL)
doc = REXML::Document.new(xml)
posts = []

doc.elements.each("rss/channel/item") do |item|
  title = child_text(item, "title")
  next if title.nil? || title.empty?

  link = child_text(item, "link")
  slug = slug_from_link(link)
  next if slug.nil? || slug.empty?

  pub_date = child_text(item, "pubDate")
  date = pub_date ? Time.parse(pub_date).strftime("%Y-%m-%d") : nil
  next if date.nil?

  body = child_text(item, "encoded")
  body = child_text(item, "description") if body.nil? || body.empty?
  next if body.nil? || body.empty?

  subtitle = plain_text(child_text(item, "description"))
  subtitle = nil if subtitle.empty? || subtitle == plain_text(body)

  posts << {
    "slug" => slug,
    "title" => title,
    "date" => date,
    "canonical" => link,
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
