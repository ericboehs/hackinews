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

  # Every uncached child referenced anywhere in the cached trees, found in one
  # query for all roots at once. This replaces walking the tree in Ruby: the old
  # worker called prefetch on every cached node each cycle just to discover the
  # handful that were new. Batching all roots into a single query rather than
  # one query per story is a large measured saving. Traversal starts only from
  # roots that are already cached; ids not in the table discover nothing.
  MISSING_DESCENDANTS_SQL = <<~SQL
    WITH RECURSIVE tree AS (
      SELECT i.id, i.data FROM items i WHERE i.id IN (?)
      UNION ALL
      SELECT c.id, c.data
      FROM tree t
      CROSS JOIN LATERAL jsonb_array_elements_text(t.data->'kids') AS k(kid)
      JOIN items c ON c.id = k.kid::bigint
    ) CYCLE id SET is_cycle USING path
    SELECT DISTINCT k.kid::bigint AS id
    FROM tree t
    CROSS JOIN LATERAL jsonb_array_elements_text(t.data->'kids') AS k(kid)
    WHERE NOT EXISTS (SELECT 1 FROM items i WHERE i.id = k.kid::bigint)
  SQL

  def self.missing_descendant_ids(root_ids)
    root_ids = Array(root_ids).compact
    return [] if root_ids.empty?

    connection.select_values(sanitize_sql_array([MISSING_DESCENDANTS_SQL, root_ids])).map(&:to_i)
  end

  # Fetches only the descendants we do not already have. Each round can reveal
  # another level (a newly fetched comment brings its own kids), so it repeats
  # until nothing new arrives. A round that inserts nothing stops immediate
  # retries of unavailable ids; max_rounds bounds how deep one pass will chase
  # newly revealed levels when inserts keep succeeding.
  def self.backfill(root_ids, max_rounds: 25)
    fetched = 0
    settled = false

    max_rounds.times do
      missing = missing_descendant_ids root_ids
      if missing.empty?
        settled = true
        break
      end

      gained = missing.count { |id| store_missing id }
      fetched += gained
      if gained.zero?
        settled = true
        break
      end
    end

    App.logger.warn "Backfill hit its #{max_rounds}-round cap; descendants remain uncached" unless settled
    fetched
  end

  def self.store_missing(id)
    payload = hn_client.item id
    return false unless payload

    create! id: id, data: payload
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Refreshes the items HN says changed, limited to ones we already cache.
  # The updates feed covers all of HN, so most ids are irrelevant to us.
  def self.sync_updates
    ids = hn_client.updated_item_ids
    if ids.nil?
      # Not fatal: the reconcile sweep below is the safety net, so a failed poll
      # delays convergence rather than breaking it.
      App.logger.error 'Updates feed unavailable; relying on reconcile sweep'
      return nil
    end

    known = where(id: ids).pluck(:id)
    failed = known.reject { |id| refresh id }
    App.logger.warn "Updates refresh failed for: #{failed.join(', ')}" if failed.any?
    App.logger.info "Updates feed: #{ids.size} changed, #{known.size} cached, #{known.size - failed.size} refreshed"
    known.size - failed.size
  end

  # How many least-recently-updated items each cycle re-checks. Tunable so the
  # sweep can be traded against convergence time without a deploy.
  def self.reconcile_batch
    Integer ENV.fetch('RECONCILE_BATCH', '500')
  end

  # The updates feed is a snapshot of what changed at poll time, not a cursor we
  # can replay. An update published between polls is gone before we see it, and
  # because discovery reads our own cached kids list, a reply we never learned
  # about can never be found. This sweep re-fetches the least recently updated
  # items so every cached row is eventually re-checked no matter what the feed
  # missed, at a cost per cycle that is fixed rather than proportional to the
  # size of the cache.
  def self.reconcile(limit: reconcile_batch)
    ids = order(:updated_at).limit(limit).pluck(:id)
    return 0 if ids.empty?

    refreshed = ids.count { |id| refresh id }
    App.logger.info "Reconciled #{refreshed}/#{ids.size} least recently updated items"
    refreshed
  end

  def self.refresh(id)
    item = find_by id: id
    return false unless item

    payload = hn_client.item id
    return false unless payload

    item.update! data: payload, updated_at: Time.now.utc
    true
  end

  def self.prefetch(id)
    item = Item.find_by id: id

    return [id, :fresh] if item && item.updated_at > 10.minutes.ago

    payload = hn_client.item id
    unless payload
      if item
        App.logger.warn "Using stale cache for item #{id}; fetch failed"
        return [id, :stale]
      end
      return [nil, :missing]
    end

    if item
      item.update! data: payload, updated_at: Time.now.utc
    else
      item = Item.create!(id: id, data: payload)
    end
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
