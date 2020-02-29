# frozen_string_literal: true

require 'active_record'
require 'sinatra'
require './lib/hacker_news_api/client'

# The App
class App < Sinatra::Base
  MIN_SCORES = [0, 50, 100, 200, 300, 400, 500, 750, 1000].freeze

  def self.boot
    url = ENV['DATABASE_URL'] || 'postgres://localhost/hackinews_development'
    ActiveRecord::Base.establish_connection url
  end

  get '/' do
    @min_score = params['min_score'].to_i || 50
    @next_min_score = MIN_SCORES[(MIN_SCORES.index(@min_score) || 0) + 1] || Float::INFINITY
    @stories = Item.top_stories min_score: @min_score
    erb :index
  end

  private

  def client
    @client ||= HackerNewsApi::Client.new
  end
end

# HackerNews Item (Story, Comment, etc)
class Item < ActiveRecord::Base
  def self.top_stories(min_score: 50)
    Item
      .where(id: hn_client.top_story_ids.map { |id| prefetch id })
      .where("(data->'score')::int > ?", min_score)
      .order(Arel.sql("data->'time' desc"))
  end

  # def self.front_page_stories
  #   front_page_stories = hn_client.search "/search_by_date?tags=story&numericFilters=created_at_i>1582917782&hitsPerPage=1000"
  # end

  def self.prefetch(id)
    exists?(id) ? id : Item.create(id: id, data: hn_client.item(id)).id
  end

  def self.hn_client
    @hn_client ||= HackerNewsApi::Client.new
  end

  def comments_url
    "https://news.ycombinator.com/item?id=#{data['id']}"
  end
end

App.boot
