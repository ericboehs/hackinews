# frozen_string_literal: true

require 'uri'
require_relative '../lib/hacker_news_api/client'

# HackerNews Item (Story, Comment, etc)
class Item < ActiveRecord::Base
  EXTENDED_TRUNCATION_DOMAINS = %w[github.com twitter.com x.com medium.com].freeze

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
    where "(data->>'type') = 'story'"
  end

  def self.title_matches(search)
    where "(data->>'title') ilike ?", "%#{search}%"
  end

  def self.prefetch(id)
    item = Item.find_by id: id
    payload = hn_client.item id
    return id unless payload

    if item && item.updated_at > 10.minutes.ago
      id
    elsif item
      item.update data: payload, updated_at: Time.now.utc
      item.prefetch_children
      item.id
    else
      item = Item.create(id: id, data: payload)
      item.prefetch_children
      item.id
    end
  rescue StandardError => e
    App.logger.error "Failed to prefetch item #{id}: #{e}"
    nil
  end

  def self.remove_old_comments
    recent_story_ids = Item.stories.last(200).pluck :id
    old_story_ids = Item.stories.where.not(id: recent_story_ids).pluck :id
    Item.where("(data->'parent')::numeric IN (?)", old_story_ids).delete_all
  end

  def prefetch_children
    return unless data && data['kids']

    data['kids']
      .map { |kid| Item.prefetch kid }
      .compact
      .map { |id| Item.find_by id: id }
      .compact
      .map(&:prefetch_children)
  end

  def truncated_url
    return unless data && data['url']

    sanitized = data['url'].delete('#%')
                           .encode('ASCII', invalid: :replace, undef: :replace, replace: '')
    uri = URI.parse sanitized
    host = uri.host
    return unless host
    return host unless EXTENDED_TRUNCATION_DOMAINS.include? host

    username = uri.path.to_s[%r{/[^/]*}]
    "#{host}#{username}"
  rescue URI::InvalidURIError
    nil
  end

  def self.hn_client
    @hn_client ||= HackerNewsApi::Client.new
  end

  def comments_url
    "https://news.ycombinator.com/item?id=#{data['id']}"
  end

  def comments
    data['kids']&.map { |kid| Item.find_by id: kid }&.compact
  end
end
