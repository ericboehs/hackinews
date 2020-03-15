# frozen_string_literal: true

require_relative '../lib/hacker_news_api/client'

# HackerNews Item (Story, Comment, etc)
class Item < ActiveRecord::Base
  def self.top_stories
    Item.where id: hn_client.top_story_ids.map { |id| prefetch id }
  end

  def self.min_score(score = 50)
    where "(data->'score')::int > ?", score
  end

  def self.by_time
    order(Arel.sql("data->'time' desc"))
  end

  def self.stories
    where "(data->'type')::text like '%story%'"
  end

  def self.prefetch(id)
    item = Item.find_by id: id

    if item && item.updated_at > 10.minutes.ago
      id
    elsif item
      item.update data: hn_client.item(id), updated_at: Time.now.utc
      item.prefetch_children
      item.id
    else
      item = Item.create(id: id, data: hn_client.item(id)).id rescue nil
      item&.prefetch_children
    end
  end

  def self.remove_old_comments
    recent_story_ids = Item.stories.last(200).pluck :id
    old_story_ids = Item.stories.where.not(id: recent_story_ids).pluck :id
    Item.where("(data->'parent')::numeric IN (?)", old_story_ids).delete_all
  end

  def prefetch_children
    return unless data['kids']

    data['kids']
      .map { |kid| Item.prefetch kid }
      .map { |id| Item.find id }
      .map(&:prefetch_children)
  end

  def self.hn_client
    HackerNewsApi::Client.new
  end

  def comments_url
    "https://news.ycombinator.com/item?id=#{data['id']}"
  end

  def comments
    data['kids']&.map { |kid| Item.find_by id: kid }&.compact
  end
end
