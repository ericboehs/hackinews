# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    App
  end

  def test_home_page
    get '/'
    assert last_response.ok?
    assert_match(/HackiNews/, last_response.body)
  end

  def test_home_page_with_min_score
    get '/', min_score: '200'
    assert last_response.ok?
  end
end
