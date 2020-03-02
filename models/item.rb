# frozen_string_literal: true

# HackerNews Item (Story, Comment, etc)
class Item < ActiveRecord::Base
  def self.top_stories(min_score: 50)
    Item
      .where(id: hn_client.top_story_ids.map { |id| prefetch id })
      .where("(data->'score')::int > ?", min_score)
      .order(Arel.sql("data->'time' desc"))
  end

  def self.prefetch(id)
    item = Item.find_by id: id
    if item && item.updated_at > 10.minutes.ago
      id
    elsif item
      item.update data: hn_client.item(id), updated_at: Time.now.utc
    else
      Item.create(id: id, data: hn_client.item(id)).id
    end
  end

  def self.hn_client
    @hn_client ||= HackerNewsApi::Client.new
  end

  def comments_url
    "https://news.ycombinator.com/item?id=#{data['id']}"
  end
end
