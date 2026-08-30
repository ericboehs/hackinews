# frozen_string_literal: true

require_relative 'test_helper'

class ItemTest < Minitest::Test
  def test_prefetch_skips_api_when_fresh
    create_item id: 1, updated_at: 1.minute.ago
    client = FakeHnClient.new
    Item.hn_client = client

    assert_equal [1, :fresh], Item.prefetch(1)
    assert_empty client.calls
  end

  def test_prefetch_updates_stale_item
    item = create_item id: 1, title: 'Old', updated_at: 1.hour.ago
    Item.hn_client = FakeHnClient.new(1 => { 'id' => 1, 'title' => 'New', 'type' => 'story' })

    assert_equal [1, :refreshed], Item.prefetch(1)
    assert_equal 'New', item.reload.data['title']
  end

  def test_prefetch_creates_missing_item
    Item.hn_client = FakeHnClient.new(9 => { 'id' => 9, 'title' => 'Fresh', 'type' => 'story' })

    assert_equal [9, :refreshed], Item.prefetch(9)
    created = Item.find(9)
    assert_equal 'Fresh', created.data['title']
  end

  def test_failed_payload_keeps_cached_data
    item = create_item id: 1, title: 'Cached', updated_at: 1.hour.ago
    Item.hn_client = FakeHnClient.new(1 => nil)

    assert_equal [1, :stale], Item.prefetch(1)
    assert_equal 'Cached', item.reload.data['title']
  end

  def test_failed_payload_without_cache_returns_nil
    Item.hn_client = FakeHnClient.new(1 => nil)

    assert_equal [nil, :missing], Item.prefetch(1)
    assert_equal 0, Item.count
  end

  def test_one_failed_kid_does_not_abort_siblings
    create_item id: 1, kids: [2, 3], updated_at: 1.hour.ago
    Item.hn_client = FakeHnClient.new(
      1 => { 'id' => 1, 'type' => 'story', 'kids' => [2, 3] },
      2 => nil,
      3 => { 'id' => 3, 'type' => 'comment', 'text' => 'ok' }
    )

    Item.prefetch 1

    refute Item.exists?(2)
    assert Item.exists?(3)
    assert_equal 'ok', Item.find(3).data['text']
  end

  def test_stories_scope
    create_item id: 1, type: 'story', title: 'A story'
    create_item id: 2, type: 'comment', title: 'A comment'

    assert_equal [1], Item.stories.pluck(:id)
  end

  def test_title_matches
    create_item id: 1, title: 'Rust release'
    create_item id: 2, title: 'Python news'

    assert_equal [1], Item.title_matches('rust').pluck(:id)
  end

  def test_min_score
    create_item id: 1, score: 10
    create_item id: 2, score: 250

    assert_equal [2], Item.min_score(200).pluck(:id)
  end

  def test_nil_data_does_not_look_like_missing_kids
    item = create_item id: 1
    item.define_singleton_method(:data) { nil }
    client = FakeHnClient.new
    Item.hn_client = client

    item.prefetch_children

    assert_empty client.calls
  end

  def test_prefetch_walks_children_of_fresh_nodes
    create_item id: 1, kids: [2], updated_at: 1.minute.ago
    create_item id: 2, kids: [3], type: 'comment', updated_at: 1.minute.ago
    client = FakeHnClient.new(
      3 => { 'id' => 3, 'type' => 'comment', 'text' => 'grand' }
    )
    Item.hn_client = client

    Item.prefetch 1

    assert Item.exists?(3)
    assert_equal [3], client.calls
  end

  def test_top_stories_keeps_successes_and_drops_failures
    Item.hn_client = FakeHnClient.new(
      top_story_ids: [1, 2, 3],
      1 => { 'id' => 1, 'title' => 'One', 'type' => 'story' },
      2 => nil,
      3 => { 'id' => 3, 'title' => 'Three', 'type' => 'story' }
    )

    result = Item.top_stories
    assert_equal [1, 3], result.order(:id).pluck(:id)
  end

  def test_top_stories_returns_nil_when_ids_unavailable
    Item.hn_client = FakeHnClient.new(top_story_ids: nil)
    assert_nil Item.top_stories
  end

  def test_top_stories_raises_when_only_stale_cache
    create_item id: 1, updated_at: 1.hour.ago
    Item.hn_client = FakeHnClient.new(top_story_ids: [1], 1 => nil)

    error = assert_raises(Item::RefreshFailed) { Item.top_stories }
    assert_equal 'only stale cache served', error.message
    assert Item.exists?(1)
  end

  def test_top_stories_succeeds_when_all_fresh
    create_item id: 1, updated_at: 1.minute.ago
    Item.hn_client = FakeHnClient.new(top_story_ids: [1])

    assert_equal [1], Item.top_stories.pluck(:id)
    refute_includes Item.hn_client.calls, 1
  end

  def test_comments_empty_when_no_kids
    comments = create_item(id: 1).comments

    assert_empty comments.to_a
    refute_predicate comments, :missing?
  end

  def test_comments_reports_all_kids_missing_from_cache
    comments = create_item(id: 1, kids: [2, 3]).comments

    assert_empty comments.to_a
    assert_predicate comments, :missing?
    assert_equal [2, 3], comments.missing_ids
  end

  def test_comments_reports_partially_missing_kids
    create_item id: 2, type: 'comment'
    comments = create_item(id: 1, kids: [2, 3]).comments

    assert_equal [2], comments.map(&:id)
    assert_predicate comments, :missing?
    assert_equal [3], comments.missing_ids
    assert_equal 1, comments.missing_count
  end

  # The NOT NULL constraint keeps stored rows from having null data, so this
  # guard only covers unsaved or in-memory-modified objects.
  def test_comments_nil_when_data_is_nil
    assert_nil Item.new(id: 1).comments
  end

  def test_comments_returns_cached_kids
    create_item id: 2, type: 'comment'
    parent = create_item id: 1, kids: [2, 3]

    assert_equal [2], parent.comments.map(&:id)
  end

  def test_hidden_is_true_for_tombstones
    assert_predicate create_tombstone(id: 1), :hidden?
    assert_predicate create_tombstone(id: 2, kind: 'dead'), :hidden?
  end

  def test_hidden_is_false_for_ordinary_and_unsaved_items
    refute_predicate create_item(id: 1, type: 'comment'), :hidden?
    refute_predicate Item.new(id: 2), :hidden?
  end

  def test_comments_drops_childless_tombstones
    create_tombstone id: 2
    create_item id: 3, type: 'comment'
    comments = create_item(id: 1, kids: [2, 3]).comments

    assert_equal [3], comments.map(&:id)
  end

  # A removed comment is not a cache gap, so it must not inflate missing_ids.
  def test_dropped_tombstones_are_not_counted_as_missing
    create_tombstone id: 2
    comments = create_item(id: 1, kids: [2]).comments

    assert_empty comments.to_a
    refute_predicate comments, :missing?
  end

  # Keeping the tombstone preserves the thread; dropping it would orphan replies.
  def test_comments_keeps_tombstones_that_have_replies
    create_item id: 3, type: 'comment'
    create_tombstone id: 2, kids: [3]
    comments = create_item(id: 1, kids: [2]).comments

    assert_equal [2], comments.map(&:id)
    assert_equal [3], comments.first.comments.map(&:id)
  end

  def test_truncated_url_returns_host
    item = create_item id: 1, url: 'https://example.com/path?q=1'
    assert_equal 'example.com', item.truncated_url
  end

  def test_truncated_url_includes_x_username
    item = create_item id: 1, url: 'https://x.com/somebody/status/1'
    assert_equal 'x.com/somebody', item.truncated_url
  end

  def build_tree(root_id: 1, fanout: [4, 3, 2])
    next_id = 100
    make = lambda do |levels|
      return nil if levels.empty?

      Array.new(levels.first) do
        next_id += 1
        id = next_id
        kids = make.call(levels[1..])
        create_item id: id, type: 'comment', kids: kids
        id
      end
    end
    create_item id: root_id, kids: make.call(fanout)
  end

  def test_thread_loads_whole_tree_in_one_query
    build_tree
    nodes = Item.count

    queries = count_queries { Item.thread(1) }

    assert_equal 41, nodes
    assert_equal 1, queries
  end

  # Guards the N+1 that made a 1,420-comment story issue ~1,420 queries.
  def test_rendering_a_preloaded_thread_issues_no_further_queries
    build_tree
    index = Item.thread(1)

    walk = lambda do |item|
      set = item.comments
      set&.each { |child| walk.call(child) }
    end

    queries = count_queries { walk.call(index[1]) }

    assert_equal 0, queries
  end

  def test_thread_returns_same_comments_as_per_node_lookup
    build_tree
    preloaded = Item.thread(1)[1].comments.map(&:id).sort
    unpreloaded = Item.find(1).comments.map(&:id).sort

    assert_equal unpreloaded, preloaded
    refute_empty preloaded
  end

  def test_thread_stops_at_max_depth
    create_item id: 3, type: 'comment'
    create_item id: 2, type: 'comment', kids: [3]
    create_item id: 1, kids: [2]

    index = Item.thread(1, max_depth: 1)

    assert_includes index.keys, 2
    refute_includes index.keys, 3
  end

  def test_prune_deletes_whole_threads_not_just_direct_replies
    # Old story with a nested reply: the previous implementation deleted the
    # direct reply but orphaned the grandchild.
    create_item id: 12, type: 'comment'
    create_item id: 11, type: 'comment', kids: [12]
    create_item id: 10, title: 'Old', kids: [11]
    # Newer story that must survive.
    create_item id: 21, type: 'comment'
    create_item id: 20, title: 'New', kids: [21]

    Item.prune keep: 1

    assert_equal [20, 21], Item.order(:id).pluck(:id)
  end

  def test_prune_refuses_to_empty_the_table
    create_item id: 5, type: 'comment'

    assert_equal 0, Item.prune
    assert Item.exists?(5)
  end

  def test_prune_keeps_the_newest_stories
    create_item id: 1, title: 'Oldest'
    create_item id: 2, title: 'Middle'
    create_item id: 3, title: 'Newest'

    Item.prune keep: 2

    assert_equal [2, 3], Item.order(:id).pluck(:id)
  end
end
