# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/pride'
require 'minitest/mock'

require './app'

module ItemCleanup
  def before_setup
    super
    Item.delete_all
    Item.hn_client = nil
  end

  def after_teardown
    Item.delete_all
    Item.hn_client = nil
    super
  end
end

module ItemFactory
  def create_item(id:, title: 'Hello', score: 100, type: 'story', kids: nil,
                  updated_at: Time.now.utc, url: nil, time: Time.now.to_i)
    data = { 'id' => id, 'title' => title, 'score' => score, 'type' => type, 'time' => time }
    data['kids'] = kids if kids
    data['url'] = url if url
    Item.create!(id: id, data: data, created_at: updated_at, updated_at: updated_at)
  end
end

class FakeHnClient
  attr_reader :calls

  def initialize(payloads = {})
    @payloads = payloads
    @calls = []
  end

  def item(id)
    @calls << id
    @payloads.key?(id) ? @payloads[id] : @payloads[:default]
  end

  def top_story_ids
    @payloads[:top_story_ids]
  end
end

class Minitest::Test
  include ItemCleanup
  include ItemFactory
end
