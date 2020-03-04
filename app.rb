# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'development'

require 'bundler/setup'
Bundler.require 'default', ENV['RACK_ENV']

require 'active_record'
require './lib/hacker_news_api/client'
require './models/item'

# The App
class App < Sinatra::Base
  MIN_SCORES = [0, 50, 100, 200, 300, 400, 500, 750, 1000].freeze

  def self.boot
    url = ENV['DATABASE_URL'] || 'postgres://localhost/hackinews_development'
    ActiveRecord::Base.establish_connection url
  end

  get '/' do
    @min_score = (params['min_score'] || 50).to_i
    @next_min_score = MIN_SCORES[(MIN_SCORES.index(@min_score) || 0) + 1] || Float::INFINITY
    @stories = Item.min_score(@min_score).by_time.first 500
    erb :index
  end

  private

  def client
    @client ||= HackerNewsApi::Client.new
  end
end

App.boot
