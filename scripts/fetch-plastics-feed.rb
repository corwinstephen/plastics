#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "fileutils"
require "net/http"
require "rexml/document"
require "time"
require "yaml"

FEED_URL = "https://anchor.fm/s/f0ad9940/podcast/rss"
OUTPUT = File.expand_path("../_data/plastics.yml", __dir__)

def fetch(url, limit = 5)
  raise "Too many redirects" if limit <= 0

  uri = URI(url)
  request = Net::HTTP::Get.new(uri)
  request["User-Agent"] = "plasticspod.org-plastics-feed/1.0"
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
    return el.text.to_s.strip if el.name == local_name
  end
  nil
end

def child_attr(item, local_name, attr)
  item.elements.each do |el|
    return el.attributes[attr] if el.name == local_name && el.attributes[attr]
  end
  nil
end

def plain_text(html)
  text = html.to_s
  text = text.gsub(/<[^>]+>/, " ")
  text = CGI.unescapeHTML(text)
  text.gsub(/\s+/, " ").strip
end

xml = fetch(FEED_URL)
doc = REXML::Document.new(xml)
episodes = []

doc.elements.each("rss/channel/item") do |item|
  title = child_text(item, "title")
  next if title.nil? || title.empty?

  enclosure = item.elements["enclosure"]
  audio = enclosure ? enclosure.attributes["url"] : nil

  pub_date = child_text(item, "pubDate")
  date = pub_date ? Time.parse(pub_date).strftime("%Y-%m-%d") : nil

  episodes << {
    "title" => title,
    "description" => plain_text(child_text(item, "description")),
    "date" => date,
    "duration" => child_text(item, "duration"),
    "link" => child_text(item, "link"),
    "audio" => audio,
    "image" => child_attr(item, "image", "href")
  }
end

FileUtils.mkdir_p(File.dirname(OUTPUT))
File.write(OUTPUT, episodes.to_yaml)
puts "Wrote #{episodes.length} episodes to #{OUTPUT}"
