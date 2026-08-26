# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../worker'

class WorkerTest < Minitest::Test
  def test_run_survives_nil_top_story_ids
    Item.hn_client = FakeHnClient.new(top_story_ids: nil)

    Worker.run
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
