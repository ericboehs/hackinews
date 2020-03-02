# frozen_string_literal: true

require 'active_record'
require './lib/hacker_news_api/client'
require './models/item'

# The Worker
class Worker
  MIN_SCORES = [0, 50, 100, 200, 300, 400, 500, 750, 1000].freeze

  def self.boot
    url = ENV['DATABASE_URL'] || 'postgres://localhost/hackinews_development'
    ActiveRecord::Base.establish_connection url
  end

  def run
    Item.top_stories
  end
end

Worker.boot
Worker.new.run
