# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    App
  end

  def test_home_page
    get '/'
    assert last_response.ok?
    assert_match(/HackiNews/, last_response.body)
  end

  def test_home_page_filters_by_min_score
    create_item id: 1, title: 'Low scoring', score: 10
    create_item id: 2, title: 'High scoring', score: 250

    get '/', min_score: '200'
    assert last_response.ok?
    assert_match(/High scoring/, last_response.body)
    refute_match(/Low scoring/, last_response.body)
  end

  def test_home_page_title_search
    create_item id: 1, title: 'Rust release', score: 100
    create_item id: 2, title: 'Python news', score: 100

    get '/', q: 'Rust', min_score: '0'
    assert last_response.ok?
    assert_match(/Rust release/, last_response.body)
    refute_match(/Python news/, last_response.body)
  end

  def test_story_with_malformed_url
    create_item id: 1, title: 'Bad url', url: 'http://exa mple.com/foo', score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/Bad url/, last_response.body)
  end

  def test_story_with_uncached_comments
    create_item id: 1, title: 'Has kids', kids: [2], score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/1\s+comment is\s+not cached yet/, last_response.body)
    refute_match(/No comments/, last_response.body)
  end

  def test_story_discloses_partially_cached_comments
    create_item id: 2, type: 'comment'
    create_item id: 1, title: 'Has kids', kids: [2, 3], score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/1\s+comment is\s+not cached yet/, last_response.body)
    refute_match(/No comments/, last_response.body)
  end

  def test_story_discloses_missing_nested_replies
    create_item id: 3, type: 'comment', kids: [4]
    create_item id: 1, title: 'Has kids', kids: [3], score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/1\s+comment is\s+not cached yet/, last_response.body)
    # The notice links to the comment permalink, not the story, proving the
    # parent is threaded through the recursive render.
    assert_match(%r{not cached yet.*?item\?id=3}m, last_response.body)
  end

  def test_story_with_fully_cached_comments_shows_no_warning
    create_item id: 2, type: 'comment'
    create_item id: 3, type: 'comment'
    create_item id: 1, title: 'Has kids', kids: [2, 3], score: 100

    get '/stories/1'
    assert last_response.ok?
    refute_match(/not cached yet/, last_response.body)
    refute_match(/No comments/, last_response.body)
  end

  def test_story_pluralizes_missing_comment_notice
    create_item id: 1, title: 'Has kids', kids: [2, 3], score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/2\s+comments are\s+not cached yet/, last_response.body)
  end

  def test_story_hides_deleted_comment_shell
    # Reproduces the empty comment seen in production: HN item 49494172 was
    # {deleted: true} with no author or text, so it rendered as a bare timestamp.
    create_tombstone id: 2
    create_item id: 3, type: 'comment'
    create_item id: 1, title: 'Has kids', kids: [2, 3], score: 100

    get '/stories/1'
    assert last_response.ok?
    refute_match(/id="2"/, last_response.body)
    refute_match(/not cached yet/, last_response.body)
    assert_match(/id="3"/, last_response.body)
  end

  def test_story_shows_placeholder_for_deleted_comment_with_replies
    create_item id: 3, type: 'comment'
    create_tombstone id: 2, kids: [3]
    create_item id: 1, title: 'Has kids', kids: [2], score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/\[deleted\]/, last_response.body)
    assert_match(/Comment removed/, last_response.body)
    assert_match(/id="3"/, last_response.body)
  end

  def test_story_with_only_deleted_comments_says_no_comments
    create_tombstone id: 2
    create_item id: 1, title: 'All gone', kids: [2], score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/No comments/, last_response.body)
  end

  def test_story_with_no_comments_says_so
    create_item id: 1, title: 'Lonely', score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/No comments/, last_response.body)
    refute_match(/not cached yet/, last_response.body)
  end

  def test_suite_connects_to_test_database
    db = ActiveRecord::Base.connection_db_config.database.to_s
    assert db.end_with?('_test'), db
  end

  # VERBOSE is set explicitly rather than assumed unset, so the suite still
  # passes when run as `VERBOSE=1 bundle exec rake test`.
  def test_logs_are_quiet_under_test_unless_verbose
    with_env 'VERBOSE' => '' do
      assert_predicate App, :quiet_logs?
      assert_equal IO::NULL, App.log_device
    end

    with_env 'VERBOSE' => '1' do
      refute_predicate App, :quiet_logs?
      assert_same $stdout, App.log_device
    end
  end

  def test_logs_are_not_quiet_outside_test
    with_env 'RACK_ENV' => 'production', 'VERBOSE' => '' do
      refute_predicate App, :quiet_logs?
      assert_same $stdout, App.log_device
    end
  end
end
