# frozen_string_literal: true

require 'uri'
require_relative '../lib/hacker_news_api/client'

# HackerNews Item (Story, Comment, etc)
class Item < ActiveRecord::Base
  class RefreshFailed < StandardError; end

  # Loaded comments plus the ids that were not in the cache, so a view can tell
  # "no comments" apart from "some comments are missing" at every nesting level.
  class CommentSet
    include Enumerable

    attr_reader :records, :missing_ids

    def initialize(records, missing_ids)
      @records = records.freeze
      @missing_ids = missing_ids.freeze
    end

    def each(&block)
      records.each(&block)
    end

    def empty?
      records.empty?
    end

    def missing?
      missing_ids.any?
    end

    def missing_count
      missing_ids.size
    end
  end

  EXTENDED_TRUNCATION_DOMAINS = %w[github.com twitter.com x.com medium.com].freeze

  def self.top_stories
    ids = hn_client.top_story_ids
    unless ids
      App.logger.error 'Failed to fetch top story IDs'
      return nil
    end

    results = ids.map { |id| prefetch id }
    served_ids = results.filter_map { |id, _status| id }
    stale = results.count { |_, status| status == :stale }
    refreshed = results.count { |_, status| status == :refreshed }
    missing = results.count { |_, status| status == :missing }

    if ids.empty?
      App.logger.warn 'Top stories list was empty'
    elsif served_ids.empty?
      App.logger.error "Prefetch failed for all #{ids.size} top stories"
    elsif stale.positive? && refreshed.zero?
      App.logger.error "Prefetch served only stale cache (#{stale} stale, #{missing} missing)"
      raise RefreshFailed, 'only stale cache served'
    elsif stale.positive? || missing.positive?
      App.logger.warn "Prefetch: #{refreshed} refreshed, #{stale} stale, #{missing} missing"
    end

    Item.where id: served_ids
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

    if item && item.updated_at > 10.minutes.ago
      item.prefetch_children
      return [id, :fresh]
    end

    payload = hn_client.item id
    unless payload
      if item
        App.logger.warn "Using stale cache for item #{id}; fetch failed"
        item.prefetch_children
        return [id, :stale]
      end
      return [nil, :missing]
    end

    if item
      item.update! data: payload, updated_at: Time.now.utc
    else
      item = Item.create!(id: id, data: payload)
    end
    item.prefetch_children
    [item.id, :refreshed]
  end

  def self.remove_old_comments
    recent_story_ids = Item.stories.last(200).pluck :id
    old_story_ids = Item.stories.where.not(id: recent_story_ids).pluck :id
    Item.where("(data->'parent')::numeric IN (?)", old_story_ids).delete_all
  end

  def prefetch_children
    if data.nil?
      App.logger.error "Item #{id} has nil data; skipping children"
      return
    end
    return unless data['kids']

    data['kids'].each { |kid| Item.prefetch kid }
  end

  def truncated_url
    if data.nil?
      App.logger.error "Item #{id} has nil data"
      return nil
    end
    return unless data['url']

    sanitized = data['url'].delete('#%')
                           .encode('ASCII', invalid: :replace, undef: :replace, replace: '')
    uri = URI.parse sanitized
    host = uri.host
    return unless host
    return host unless EXTENDED_TRUNCATION_DOMAINS.include? host

    username = uri.path.to_s[%r{/[^/]*}]
    "#{host}#{username}"
  rescue URI::InvalidURIError => e
    App.logger.warn "Item #{id} has invalid URL #{data['url'].inspect}: #{e}"
    nil
  end

  def self.hn_client
    @hn_client ||= HackerNewsApi::Client.new
  end

  def self.hn_client=(client)
    @hn_client = client
  end

  # HN keeps tombstones for removed comments. Deleted ones carry no author or
  # text at all, so rendering them yields an empty shell; dead ones are
  # moderated out of the default view but can still carry text. Whether a
  # tombstone is shown is decided in #comments, not here.
  def hidden?
    return false if data.nil?

    !!(data['deleted'] || data['dead'])
  end

  def replies?
    !data.nil? && data['kids'].present?
  end

  def comments_url
    "https://news.ycombinator.com/item?id=#{data['id']}"
  end

  def comments
    if data.nil?
      App.logger.error "Item #{id} has nil data"
      return nil
    end

    kids = data['kids']
    return CommentSet.new([], []) if kids.blank?

    loaded = kids.index_with { |kid| Item.find_by id: kid }
    missing = loaded.select { |_, rec| rec.nil? }.keys
    App.logger.warn "Item #{id} missing cached comments: #{missing.join(', ')}" if missing.any?

    # A tombstone with no replies has nothing to show and nothing to anchor, so
    # drop it. It is removed rather than missing, so it stays out of missing_ids.
    visible = loaded.values.compact.reject { |rec| rec.hidden? && !rec.replies? }

    CommentSet.new(visible, missing)
  end
end
