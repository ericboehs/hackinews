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

  def test_home_page_filters_by_min_score
    create_item id: 1, title: 'Low scoring', score: 10
    create_item id: 2, title: 'High scoring', score: 250

    get '/', min_score: '200'
    assert last_response.ok?
    assert_match(/High scoring/, last_response.body)
    refute_match(/Low scoring/, last_response.body)
  end

  def test_home_page_title_search
    create_item id: 1, title: 'Rust release', score: 100
    create_item id: 2, title: 'Python news', score: 100

    get '/', q: 'Rust', min_score: '0'
    assert last_response.ok?
    assert_match(/Rust release/, last_response.body)
    refute_match(/Python news/, last_response.body)
  end
end
