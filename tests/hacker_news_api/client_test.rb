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

    def test_http_options_enable_ssl_and_timeouts
      assert_equal true, Client::HTTP_OPTIONS[:use_ssl]
      assert_equal 5, Client::HTTP_OPTIONS[:open_timeout]
      assert_equal 10, Client::HTTP_OPTIONS[:read_timeout]
    end
  end
end
