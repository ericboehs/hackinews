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

  # data is NOT NULL, so this is only reachable for an unsaved record.
  def test_comments_nil_when_data_is_nil
    assert_nil Item.new(id: 1).comments
  end

  def test_comments_returns_cached_kids
    create_item id: 2, type: 'comment'
    parent = create_item id: 1, kids: [2, 3]

    assert_equal [2], parent.comments.map(&:id)
  end

  def test_truncated_url_returns_host
    item = create_item id: 1, url: 'https://example.com/path?q=1'
    assert_equal 'example.com', item.truncated_url
  end

  def test_truncated_url_includes_x_username
    item = create_item id: 1, url: 'https://x.com/somebody/status/1'
    assert_equal 'x.com/somebody', item.truncated_url
  end
end
