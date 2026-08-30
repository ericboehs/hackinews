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

  # Expanding kids with CROSS JOIN LATERAL rather than `id IN (SELECT
  # jsonb_array_elements_text(...))` is load-bearing: the IN form plans as a
  # nested loop over the whole table and is orders of magnitude slower. CYCLE
  # makes the walk terminate on a cycle in the data without capping depth, so
  # deep threads are returned in full.
  THREAD_SQL = <<~SQL
    WITH RECURSIVE tree AS (
      SELECT i.id, i.data, i.created_at, i.updated_at FROM items i WHERE i.id = ?
      UNION ALL
      SELECT c.id, c.data, c.created_at, c.updated_at
      FROM tree t
      CROSS JOIN LATERAL jsonb_array_elements_text(t.data->'kids') AS k(kid)
      JOIN items c ON c.id = k.kid::bigint
    ) CYCLE id SET is_cycle USING path
    SELECT id, data, created_at, updated_at FROM tree
  SQL

  # Loads a comment tree in one query and points every record at the shared
  # index, so rendering the thread issues no further queries.
  def self.thread(root_id)
    records = find_by_sql [THREAD_SQL, root_id]
    index = records.index_by(&:id)
    records.each { |record| record.comment_index = index }
    index
  end

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

  # The old implementation matched `data->'parent' IN (old story ids)`, which
  # only ever deleted a story's *direct* replies -- every nested reply beneath
  # them was orphaned and kept forever. Walking the tree deletes whole threads.
  # CYCLE rather than a depth cap matters here: a cap would classify deep
  # descendants of a *retained* story as unreachable and delete them.
  PRUNE_SQL = <<~SQL
    WITH RECURSIVE keep AS (
      SELECT i.id, i.data FROM items i WHERE i.id IN (?)
      UNION ALL
      SELECT c.id, c.data
      FROM keep k
      CROSS JOIN LATERAL jsonb_array_elements_text(k.data->'kids') AS kk(kid)
      JOIN items c ON c.id = kk.kid::bigint
    ) CYCLE id SET is_cycle USING path
    DELETE FROM items WHERE NOT EXISTS (SELECT 1 FROM keep WHERE keep.id = items.id)
  SQL

  # Deletes every item not reachable from the given stories. The retained set is
  # always supplied by the caller -- the worker passes the current top-story
  # list -- so the cache tracks what the site actually serves and evicts stories
  # as they rotate off. There is deliberately no default: measured against
  # production, a "keep the newest N stories" heuristic evicted 80% of the cache
  # including stories still on the front page, which the worker then refetched.
  def self.prune(keep_ids)
    keep_ids = Array(keep_ids).compact
    # Without this the keep set is empty and the delete would wipe the table.
    if keep_ids.empty?
      App.logger.warn 'Prune skipped: no stories to keep'
      return 0
    end

    deleted = connection.delete sanitize_sql_array([PRUNE_SQL, keep_ids])
    App.logger.info "Pruned #{deleted} items outside #{keep_ids.size} retained stories"
    deleted
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

  # Set when the record came from .thread, letting #comments resolve children
  # from memory instead of querying per node.
  attr_accessor :comment_index

  def comments
    if data.nil?
      App.logger.error "Item #{id} has nil data"
      return nil
    end

    kids = data['kids']
    return CommentSet.new([], []) if kids.blank?

    loaded = kids.index_with { |kid| lookup_child kid }
    missing = loaded.select { |_, rec| rec.nil? }.keys
    App.logger.warn "Item #{id} missing cached comments: #{missing.join(', ')}" if missing.any?

    # A tombstone with no replies has nothing to show and nothing to anchor, so
    # drop it. It is removed rather than missing, so it stays out of missing_ids.
    visible = loaded.values.compact.reject { |rec| rec.hidden? && !rec.replies? }

    CommentSet.new(visible, missing)
  end

  private

  def lookup_child(kid)
    return comment_index[kid] if comment_index

    Item.find_by id: kid
  end
end
