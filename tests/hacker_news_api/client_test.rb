# frozen_string_literal: true

require_relative '../test_helper'

module HackerNewsApi
  class ClientTest < Minitest::Test
    def client
      @client ||= Client.new
    end

    def stub_http(response_or_error)
      client.stub :request, response_or_error do
        yield
      end
    end

    def response(code:, body:)
      Struct.new(:code, :body).new(code, body)
    end

    def test_top_story_ids_parses_json
      stub_http(response(code: '200', body: '[1,2,3]')) do
        assert_equal [1, 2, 3], client.top_story_ids
      end
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
