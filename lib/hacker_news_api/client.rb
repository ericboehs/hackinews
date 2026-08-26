# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module HackerNewsApi
  # Interfaces with Hacker News API
  class Client
    DEFAULT_COMMENT_LIMIT = 30

    def top_story_ids
      get "#{base_url}/topstories.json"
    end

    def best_story_ids
      get "#{base_url}/beststories.json"
    end

    def new_story_ids
      get "#{base_url}/newstories.json"
    end

    def comments(item_json, limit = DEFAULT_COMMENT_LIMIT)
      Array(item_json['kids']).first(limit).map { |kid| item kid }
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
      logger.info "#{self.class}: Fetching #{endpoint}"

      uri = URI endpoint
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: true, open_timeout: 5, read_timeout: 10
      ) do |http|
        http.request Net::HTTP::Get.new(uri)
      end

      raise "Non-200: #{response.code}" unless (200..299).cover? response.code.to_i

      JSON.parse response.body
    rescue StandardError => e
      logger.error "#{self.class}: Failed get request: #{e}; " \
                   "Response: #{response&.code} #{response&.body}"
      nil
    end

    private

    def logger
      App.logger
    end

    def base_url
      'https://hacker-news.firebaseio.com/v0'
    end
  end
end
