# frozen_string_literal: true

require 'net/http'
require 'lightly'

module HackerNewsApi
  # Interfaces with Hacker News API
  class Client
    LIMIT = 30

    def top_stories(limit = LIMIT)
      top_story_ids
        .first(limit)
        .map { |top_story| story top_story }
        .compact
        .sort_by { |story| story[:time] }
        .reverse
    end

    def top_story_ids
      get "#{base_url}/topstories.json"
    end

    def best_story_ids
      get "#{base_url}/beststories.json"
    end

    def new_story_ids
      get "#{base_url}/newstories.json"
    end

    def comments(item_json, limit = LIMIT)
      item_json['kids'].first(limit).map { |kid| item kid }
    end

    def comment(id)
      item id
    end

    def story(id)
      item id
    end

    def item(id)
      get "#{base_url}/item/#{id}.json"
    end

    def get(endpoint)
      $stdout.puts "#{self.class}: Fetching #{endpoint}"

      uri = URI endpoint
      request = Net::HTTP::Get.new uri
      http = Net::HTTP.start uri.host, uri.port, use_ssl: true
      raw_response = Lightly.get(endpoint) { http.request request }
      JSON.parse raw_response.body, symbolize_names: true
    end

    private

    def base_url
      'https://hacker-news.firebaseio.com/v0'
    end
  end
end
