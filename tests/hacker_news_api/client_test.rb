# frozen_string_literal: true

require_relative '../test_helper'

module HackerNewsApi
  class ClientTest < Minitest::Test
    BODY_LIMIT = Client::BODY_LOG_LIMIT

    def client
      @client ||= Client.new
    end

    def stub_http(response_or_error)
      client.stub :request, response_or_error do
        yield
      end
    end

    def response(code:, body:, headers: {})
      Struct.new(:code, :body, :headers) do
        def [](name)
          headers[name]
        end
      end.new(code, body, headers)
    end

    def test_top_story_ids_parses_json
      stub_http(response(code: '200', body: '[1,2,3]')) do
        assert_equal [1, 2, 3], client.top_story_ids
      end
    end

    # Guards the response shape: updates.json returns an object, not an array,
    # so returning the whole payload would break `where(id: ids)`.
    def test_updated_item_ids_extracts_the_items_key
      body = '{"items":[1,2,3],"profiles":["pg"]}'
      stub_http(response(code: '200', body: body)) do
        assert_equal [1, 2, 3], client.updated_item_ids
      end
    end

    def test_updated_item_ids_returns_nil_on_failure
      stub_http(response(code: '500', body: 'nope')) do
        assert_nil client.updated_item_ids
      end
    end

    def test_updated_item_ids_requests_the_updates_endpoint
      requested = nil
      client.stub :get, ->(url) { requested = url } do
        client.updated_item_ids
      end

      assert_match(%r{/v0/updates\.json\z}, requested)
    end

    def test_item_parses_json
      stub_http(response(code: '200', body: '{"id":42,"score":10}')) do
        assert_equal({ 'id' => 42, 'score' => 10 }, client.item(42))
      end
    end

    def test_http_500_returns_nil
      stub_http(response(code: '500', body: 'nope')) do
        assert_nil client.item(1)
      end
    end

    def test_failure_logs_status_and_body
      out = capture_log do
        stub_http(response(code: '503', body: 'upstream is down')) { client.item(1) }
      end
      assert_match(/HTTP 503/, out)
      assert_match(/upstream is down/, out)
    end

    def test_failure_logs_retry_after_when_throttled
      out = capture_log do
        stub_http(response(code: '429', body: 'slow down', headers: { 'Retry-After' => '120' })) do
          client.item(1)
        end
      end
      assert_match(/HTTP 429/, out)
      assert_match(/retry-after="120"/, out)
    end

    def test_failure_body_is_truncated
      out = capture_log do
        stub_http(response(code: '500', body: "#{'x' * BODY_LIMIT}CUTOFF-MARKER")) { client.item(1) }
      end
      assert_match(/x{#{BODY_LIMIT}}/, out)
      refute_match(/CUTOFF-MARKER/, out)
    end

    def test_failure_omits_retry_after_when_absent
      out = capture_log do
        stub_http(response(code: '500', body: 'boom')) { client.item(1) }
      end
      refute_match(/retry-after/, out)
    end

    def test_timeout_returns_nil
      stub_http(->(*) { raise Net::OpenTimeout, 'slow' }) do
        assert_nil client.top_story_ids
      end
    end

    def test_read_timeout_returns_nil
      stub_http(->(*) { raise Net::ReadTimeout, 'slow' }) do
        assert_nil client.item(1)
      end
    end

    def test_malformed_json_returns_nil
      stub_http(response(code: '200', body: 'not-json')) do
        assert_nil client.item(1)
      end
    end

    def test_socket_error_returns_nil
      stub_http(->(*) { raise SocketError, 'dns' }) do
        assert_nil client.top_story_ids
      end
    end

    def test_unexpected_error_is_raised
      stub_http(->(*) { raise NoMethodError, 'bug' }) do
        assert_raises(NoMethodError) { client.item(1) }
      end
    end

    def test_write_timeout_returns_nil
      stub_http(->(*) { raise Net::WriteTimeout }) do
        assert_nil client.item(1)
      end
    end

    def test_eof_error_returns_nil
      stub_http(->(*) { raise EOFError }) do
        assert_nil client.item(1)
      end
    end

    def test_epipe_returns_nil
      stub_http(->(*) { raise Errno::EPIPE }) do
        assert_nil client.item(1)
      end
    end

    def test_emfile_is_raised
      stub_http(->(*) { raise Errno::EMFILE }) do
        assert_raises(Errno::EMFILE) { client.item(1) }
      end
    end

    def test_request_passes_ssl_host_and_timeouts
      captured = nil
      fake_response = response(code: '200', body: '[]')
      original = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |host, port = nil, *_rest, **opts, &blk|
        captured = { host: host, port: port, opts: opts }
        http = Object.new
        http.define_singleton_method(:request) { |_| fake_response }
        blk.call http
      end

      result = client.send(:request, URI('https://hacker-news.firebaseio.com/v0/topstories.json'))

      assert_equal fake_response, result
      assert_equal 'hacker-news.firebaseio.com', captured[:host]
      assert_equal 443, captured[:port]
      assert_equal true, captured[:opts][:use_ssl]
      assert_equal 5, captured[:opts][:open_timeout]
      assert_equal 10, captured[:opts][:read_timeout]
    ensure
      Net::HTTP.define_singleton_method(:start, original)
    end
  end
end
