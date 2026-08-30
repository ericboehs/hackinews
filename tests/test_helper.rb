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
                  updated_at: Time.now.utc, url: nil, time: Time.now.to_i,
                  deleted: false, dead: false, by: nil, text: nil)
    data = { 'id' => id, 'title' => title, 'score' => score, 'type' => type, 'time' => time }
    data['kids'] = kids if kids
    data['url'] = url if url
    data['by'] = by if by
    data['text'] = text if text
    data['deleted'] = true if deleted
    data['dead'] = true if dead
    Item.create!(id: id, data: data, created_at: updated_at, updated_at: updated_at)
  end

  # Minimal deleted/dead comment fixture: no author, text, or title, mirroring
  # what HN returns for a tombstone. Accepts kids so threaded cases can be built.
  def create_tombstone(id:, kind: 'deleted', kids: nil, time: Time.now.to_i)
    data = { 'id' => id, 'type' => 'comment', 'time' => time, kind => true }
    data['kids'] = kids if kids
    Item.create!(id: id, data: data, created_at: Time.now.utc, updated_at: Time.now.utc)
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

  def updated_item_ids
    @calls << :updated_item_ids
    @payloads[:updated_item_ids]
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

module QueryCounter
  # Counts real SQL against the database, ignoring cached/schema statements, so
  # tests can assert that thread rendering stays O(1) queries.
  def count_queries
    count = 0
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
      name = payload[:name].to_s
      count += 1 unless payload[:cached] || %w[SCHEMA TRANSACTION].include?(name)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe sub
  end
end

class Minitest::Test
  include ItemCleanup
  include ItemFactory
  include LogCapture
  include EnvHelper
  include QueryCounter
end
