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
end
