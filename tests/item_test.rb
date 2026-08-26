# frozen_string_literal: true

require_relative 'test_helper'

class ItemTest < Minitest::Test
  def test_prefetch_skips_api_when_fresh
    create_item id: 1, updated_at: 1.minute.ago
    client = FakeHnClient.new
    Item.hn_client = client

    assert_equal 1, Item.prefetch(1)
    assert_empty client.calls
  end

  def test_prefetch_updates_stale_item
    item = create_item id: 1, title: 'Old', updated_at: 1.hour.ago
    Item.hn_client = FakeHnClient.new(1 => { 'id' => 1, 'title' => 'New', 'type' => 'story' })

    assert_equal 1, Item.prefetch(1)
    assert_equal 'New', item.reload.data['title']
  end

  def test_prefetch_creates_missing_item
    Item.hn_client = FakeHnClient.new(9 => { 'id' => 9, 'title' => 'Fresh', 'type' => 'story' })

    assert_equal 9, Item.prefetch(9)
    created = Item.find(9)
    assert_equal 'Fresh', created.data['title']
  end

  def test_failed_payload_keeps_cached_data
    item = create_item id: 1, title: 'Cached', updated_at: 1.hour.ago
    Item.hn_client = FakeHnClient.new(1 => nil)

    assert_equal 1, Item.prefetch(1)
    assert_equal 'Cached', item.reload.data['title']
  end

  def test_failed_payload_without_cache_returns_nil
    Item.hn_client = FakeHnClient.new(1 => nil)

    assert_nil Item.prefetch(1)
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
end
