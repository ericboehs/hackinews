# frozen_string_literal: true

require 'net/http'

module HackerNewsApi
  # Interfaces with Hacker News API
  class Client
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
      App.logger.info "#{self.class}: Fetching #{endpoint}"

      http, request = setup_get_request endpoint
      response = http.request request
      raise 'Non-200' unless (200..300).include? response.code.to_i

      JSON.parse response.body
    rescue StandardError => e
      handle_http_exception e, response
    end

    private

    def setup_get_request(endpoint)
      uri = URI endpoint
      request = Net::HTTP::Get.new uri
      http = Net::HTTP.start uri.host, uri.port, use_ssl: true
      [http, request]
    end

    def handle_http_exception(exception, response)
      App.logger.error "#{self.class}: Failed get request: #{exception}; " \
        "Response: #{response.code} #{response.body}"
    end

    def base_url
      'https://hacker-news.firebaseio.com/v0'
    end
  end
end
