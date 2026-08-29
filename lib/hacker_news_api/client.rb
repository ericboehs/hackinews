# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

module HackerNewsApi
  # Interfaces with Hacker News API
  class Client
    DEFAULT_COMMENT_LIMIT = 30

    # Cap on how much of a failed response body reaches the log.
    BODY_LOG_LIMIT = 200

    class FetchError < StandardError; end

    HTTP_OPTIONS = { use_ssl: true, open_timeout: 5, read_timeout: 10 }.freeze

    EXPECTED_ERRORS = [
      FetchError,
      JSON::ParserError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Net::WriteTimeout,
      OpenSSL::SSL::SSLError,
      SocketError,
      EOFError,
      Errno::EPIPE,
      Errno::ECONNABORTED,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::ETIMEDOUT
    ].freeze

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

    private

    def get(endpoint)
      logger.info "#{self.class}: Fetching #{endpoint}"

      response = request URI(endpoint)

      raise FetchError, failure_details(response) unless (200..299).cover? response.code.to_i

      JSON.parse response.body
    rescue *EXPECTED_ERRORS => e
      logger.error "#{self.class}: Failed GET #{endpoint} (#{e.class}): #{e}"
      nil
    end

    # Enough of the response to tell throttling (429 + Retry-After) apart from a
    # server fault, without dumping an unbounded body into the log.
    def failure_details(response)
      details = ["HTTP #{response.code}"]
      retry_after = response['Retry-After']
      details << "retry-after=#{retry_after.inspect}" if retry_after
      body = response.body.to_s.strip
      details << "body=#{body[0, BODY_LOG_LIMIT].inspect}" unless body.empty?
      details.join('; ')
    end

    def request(uri)
      Net::HTTP.start(uri.host, uri.port, **HTTP_OPTIONS) do |http|
        http.request Net::HTTP::Get.new(uri)
      end
    end

    def logger
      App.logger
    end

    def base_url
      'https://hacker-news.firebaseio.com/v0'
    end
  end
end
