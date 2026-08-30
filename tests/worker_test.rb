# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../worker'

class WorkerTest < Minitest::Test
  def test_run_raises_when_only_stale_cache
    create_item id: 1, updated_at: 1.hour.ago
    Item.hn_client = FakeHnClient.new(top_story_ids: [1], 1 => nil)

    assert_raises(Item::RefreshFailed) { Worker.run }
    assert Item.exists?(1)
  end

  def test_run_prunes_unreachable_items_on_success
    # Orphan comment: not reachable from any story the worker keeps.
    create_item id: 901, type: 'comment'
    Item.hn_client = FakeHnClient.new(top_story_ids: [1], 1 => { 'id' => 1, 'type' => 'story', 'title' => 'Live' })

    capture_log { Worker.run }

    assert Item.exists?(1), 'freshly fetched story should survive'
    refute Item.exists?(901), 'orphaned comment should be pruned'
  end

  def test_run_raises_when_top_story_ids_unavailable
    client = FakeHnClient.new(top_story_ids: nil)
    Item.hn_client = client

    error = assert_raises(Worker::FetchFailed) { Worker.run }

    assert_equal 'top story IDs unavailable', error.message
    assert_includes client.calls, :top_story_ids
    assert_equal 0, Item.count
  end

  def test_start_retries_after_a_failed_run
    runs = 0

    Worker.stub :interval, 0.01 do
      Worker.stub :run, lambda {
        runs += 1
        raise 'boom' if runs == 1

        throw :done
      } do
        catch(:done) { Worker.start }
      end
    end

    assert_equal 2, runs
  end

  def test_start_gives_up_after_consecutive_failures
    Worker.stub :interval, 0.01 do
      Worker.stub :max_consecutive_failures, 2 do
        Worker.stub :run, -> { raise 'boom' } do
          error = assert_raises(RuntimeError) { Worker.start }
          assert_equal 'boom', error.message
        end
      end
    end
  end

  def test_start_resets_failures_after_success
    runs = 0

    Worker.stub :interval, 0.01 do
      Worker.stub :max_consecutive_failures, 2 do
        Worker.stub :run, lambda {
          runs += 1
          case runs
          when 1, 3 then raise Worker::FetchFailed, 'outage'
          when 2 then nil
          else throw :done
          end
        } do
          catch(:done) { Worker.start }
        end
      end
    end

    assert_equal 4, runs
  end

  def test_interval_rejects_zero
    ENV['WORKER_INTERVAL'] = '0'
    assert_raises(ArgumentError) { Worker.interval }
  ensure
    ENV.delete 'WORKER_INTERVAL'
  end

  def test_interval_rejects_negative
    ENV['WORKER_INTERVAL'] = '-1'
    assert_raises(ArgumentError) { Worker.interval }
  ensure
    ENV.delete 'WORKER_INTERVAL'
  end

  # The old worker called prefetch on every cached node each cycle, so a fully
  # cached, unchanged tree cost one API request per comment. Cost is now set by
  # the reconcile budget, not by how much is cached.
  def test_steady_state_cycle_cost_is_bounded_by_the_reconcile_budget
    story = { 'id' => 1, 'type' => 'story', 'title' => 'S', 'kids' => (2..61).to_a }
    create_item id: 1, kids: (2..61).to_a, updated_at: 1.minute.ago
    (2..61).each { |i| create_item id: i, type: 'comment', updated_at: 1.minute.ago }

    client = FakeHnClient.new(top_story_ids: [1], updated_item_ids: [], 1 => story, default: nil)
    Item.hn_client = client

    with_env 'RECONCILE_BATCH' => '5' do
      capture_log { Worker.run }
    end

    assert_equal 60, Item.where.not(id: 1).count
    # 5 from the sweep, and nothing proportional to the 60 cached comments.
    assert_equal 5, client.calls.grep(Integer).size
  end

  def test_cycle_fetches_only_genuinely_new_comments
    create_item id: 1, kids: [2, 3], updated_at: 1.minute.ago
    create_item id: 2, type: 'comment', updated_at: 1.minute.ago

    client = FakeHnClient.new(
      top_story_ids: [1],
      updated_item_ids: [],
      3 => { 'id' => 3, 'type' => 'comment', 'text' => 'new' }
    )
    Item.hn_client = client

    with_env 'RECONCILE_BATCH' => '0' do
      capture_log { Worker.run }
    end

    assert_equal [3], client.calls.grep(Integer)
    assert Item.exists?(3)
  end

  # The gap the reconcile sweep exists to close, end to end: HN reports a
  # cached comment as changed, its refreshed kids list reveals a new reply,
  # and backfill must pull that reply in during the same cycle.
  def test_updated_comment_reveals_and_backfills_a_new_reply
    create_item id: 1, kids: [2], updated_at: 1.minute.ago
    create_item id: 2, type: 'comment', updated_at: 1.minute.ago

    client = FakeHnClient.new(
      top_story_ids: [1],
      updated_item_ids: [2],
      2 => { 'id' => 2, 'type' => 'comment', 'kids' => [3] },
      3 => { 'id' => 3, 'type' => 'comment', 'text' => 'the new reply' }
    )
    Item.hn_client = client

    with_env 'RECONCILE_BATCH' => '0' do
      capture_log { Worker.run }
    end

    assert Item.exists?(3), 'new reply should be discovered via the updated parent'
    assert_equal 'the new reply', Item.find(3).data['text']
  end
end
