# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
ENV['DATABASE_URL'] ||= 'postgres:///hackinews_test'

require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/pride'
require 'minitest/mock'
require 'stringio'

require './app'

db = ActiveRecord::Base.connection_db_config.database.to_s
abort "Refusing to run tests against #{db}" unless db.end_with?('_test')

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
    @calls << :top_story_ids
    @payloads[:top_story_ids]
  end
end

module LogCapture
  # Redirects App.logger to a string for the duration of the block, so tests can
  # assert on diagnostics without adding a writer to production code.
  def capture_log
    io = StringIO.new
    App.stub :logger, Logger.new(io) do
      yield
    end
    io.string
  end
end

module EnvHelper
  def with_env(vars)
    original = ENV.to_hash.slice(*vars.keys)
    ENV.update vars
    yield
  ensure
    vars.each_key { |k| original.key?(k) ? ENV[k] = original[k] : ENV.delete(k) }
  end
end

class Minitest::Test
  include ItemCleanup
  include ItemFactory
  include LogCapture
  include EnvHelper
end
