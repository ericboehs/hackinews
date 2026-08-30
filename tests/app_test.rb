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

  # dead items reach the same filter as deleted ones, but unlike deleted they
  # can still carry text, so a regression would resurrect a visible shell.
  def test_story_hides_childless_dead_comment
    create_tombstone id: 2, kind: 'dead'
    create_item id: 3, type: 'comment'
    create_item id: 1, title: 'Has kids', kids: [2, 3], score: 100

    get '/stories/1'
    assert last_response.ok?
    refute_match(/id="2"/, last_response.body)
    assert_match(/id="3"/, last_response.body)
  end

  def test_story_shows_placeholder_for_dead_comment_with_replies
    create_item id: 3, type: 'comment'
    create_tombstone id: 2, kind: 'dead', kids: [3]
    create_item id: 1, title: 'Has kids', kids: [2], score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/\[deleted\]/, last_response.body)
    assert_match(/id="3"/, last_response.body)
  end

  # kids anchors the thread even before replies are cached, so the tombstone
  # must survive and carry the gap notice rather than vanish.
  def test_story_keeps_tombstone_whose_reply_is_not_cached
    create_tombstone id: 2, kids: [3]
    create_item id: 1, title: 'Has kids', kids: [2], score: 100

    get '/stories/1'
    assert last_response.ok?
    assert_match(/\[deleted\]/, last_response.body)
    assert_match(/1\s+comment is\s+not cached yet/, last_response.body)
    assert_match(%r{not cached yet.*?item\?id=2}m, last_response.body)
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
  def test_unknown_story_returns_404
    get '/stories/999999999'

    assert_equal 404, last_response.status
    assert_match(/Story not found/, last_response.body)
    assert_match(/pruned from the cache/, last_response.body)
  end

  def test_non_numeric_story_id_returns_404
    get '/stories/not-an-id'

    assert_equal 404, last_response.status
  end

  def test_unknown_path_returns_404
    get '/nope'

    assert_equal 404, last_response.status
  end

  def test_unknown_path_uses_generic_wording
    get '/nope'

    assert_equal 404, last_response.status
    assert_match(/Page not found/, last_response.body)
    refute_match(/Story not found/, last_response.body)
  end

  # Larger than int4; would otherwise raise in the adapter and return a 500.
  def test_out_of_range_story_id_returns_404
    get '/stories/99999999999999'

    assert_equal 404, last_response.status
  end

  # --- escaping -------------------------------------------------------------

  def test_story_titles_are_escaped_on_the_homepage
    create_item id: 1, title: '<script>alert(1)</script>', score: 100

    get '/'

    refute_includes last_response.body, '<script>alert(1)</script>'
    assert_includes last_response.body, '&lt;script&gt;'
  end

  def test_story_title_and_author_are_escaped_on_the_story_page
    create_item id: 1, title: '<img src=x onerror=alert(1)>', score: 100, by: '<b>evil</b>'

    get '/stories/1'

    refute_includes last_response.body, '<img src=x onerror=alert(1)>'
    refute_includes last_response.body, '<b>evil</b>'
    assert_includes last_response.body, '&lt;img src=x'
  end

  def test_comment_author_is_escaped
    create_item id: 2, type: 'comment', by: '<script>x</script>', text: 'hi'
    create_item id: 1, score: 100, kids: [2]

    get '/stories/1'

    refute_includes last_response.body, '<script>x</script>'
  end

  # HN comment bodies are HTML and are intentionally rendered raw.
  def test_comment_html_is_still_rendered
    create_item id: 2, type: 'comment', text: 'see <a href="https://x.test">this</a>'
    create_item id: 1, score: 100, kids: [2]

    get '/stories/1'

    assert_includes last_response.body, '<a href="https://x.test">this</a>'
  end

  def test_javascript_urls_are_not_rendered_as_links
    create_item id: 1, title: 'Bad', score: 100, url: 'javascript:alert(1)'

    capture_log { get '/stories/1' }

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Bad'
    refute_includes last_response.body, 'javascript:'
    # Falls back to the HN discussion rather than rendering a dead href="".
    assert_includes last_response.body, 'news.ycombinator.com/item?id=1'
  end

  def test_javascript_urls_are_not_rendered_on_the_homepage
    create_item id: 1, title: 'Bad', score: 100, url: 'javascript:alert(1)'

    capture_log { get '/' }

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Bad'
    refute_includes last_response.body, 'javascript:'
  end

  # mailto: raises URI::InvalidComponentError, which is not a subclass of
  # URI::InvalidURIError and would otherwise 500 the page.
  def test_unparseable_url_does_not_error_the_page
    create_item id: 1, title: 'Odd', score: 100, url: 'mailto:x'

    capture_log { get '/stories/1' }

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Odd'
  end

  def test_ordinary_urls_still_render
    create_item id: 1, title: 'Good', score: 100, url: 'https://example.test/a?b=1&c=2'

    get '/stories/1'

    assert_includes last_response.body, 'https://example.test/a?b=1&amp;c=2'
  end

  # --- caching --------------------------------------------------------------

  # The dark palette is gated on .hn-dark, which only JS adds. If that gate is
  # ever removed, dark mode renders #666 text on a black background.
  def test_dark_mode_styles_are_scoped_so_the_page_survives_without_js
    create_item id: 1, title: 'A', score: 100

    get '/'
    body = last_response.body

    assert_includes body, 'prefers-color-scheme: dark'
    assert_includes body, 'html.hn-dark, html.hn-dark body { background-color: #000 }'
    # Driven by a media-query listener rather than a timer.
    assert_includes body, "addEventListener('change', applyScheme)"
  end

  def test_homepage_sends_cache_validators
    create_item id: 1, title: 'A', score: 100

    get '/'

    assert last_response.headers['ETag'], 'expected an ETag'
    cache_control = last_response.headers['Cache-Control']

    assert_includes cache_control, 'public'
    assert_includes cache_control, 'must-revalidate'
    assert_includes cache_control, 'max-age=30'
  end

  def test_homepage_returns_304_when_unchanged
    create_item id: 1, title: 'A', score: 100
    get '/'
    etag = last_response.headers['ETag']

    get '/', {}, 'HTTP_IF_NONE_MATCH' => etag

    assert_equal 304, last_response.status
    assert_empty last_response.body
  end

  def test_story_returns_304_when_unchanged
    create_item id: 2, type: 'comment', text: 'hi'
    create_item id: 1, score: 100, kids: [2]
    get '/stories/1'
    etag = last_response.headers['ETag']

    get '/stories/1', {}, 'HTTP_IF_NONE_MATCH' => etag

    assert_equal 304, last_response.status
  end

  def test_adding_a_comment_invalidates_the_story_cache
    create_item id: 1, score: 100
    get '/stories/1'
    before = last_response.headers['ETag']

    create_item id: 2, type: 'comment', text: 'brand new reply'
    Item.find(1).update! data: Item.find(1).data.merge('kids' => [2])

    get '/stories/1', {}, 'HTTP_IF_NONE_MATCH' => before

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'brand new reply'
  end

  def test_editing_a_comment_invalidates_the_story_cache
    create_item id: 2, type: 'comment', text: 'original'
    create_item id: 1, score: 100, kids: [2]
    get '/stories/1'
    before = last_response.headers['ETag']

    Item.find(2).update! data: Item.find(2).data.merge('text' => 'edited text')

    get '/stories/1', {}, 'HTTP_IF_NONE_MATCH' => before

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'edited text'
  end

  # A story leaving the score filter while another replaces it leaves both the
  # row count and the newest timestamp unchanged, so the ETag must also depend
  # on which rows are in the result.
  def test_membership_change_invalidates_the_homepage_cache
    stamp = 2.hours.ago
    501.times { |i| create_item id: i + 1, title: "Story #{i + 1}", score: 100, time: i, updated_at: stamp }
    get '/'
    before = last_response.headers['ETag']

    # Drop one displayed story below the threshold without touching the newest.
    demoted = Item.order(Arel.sql("data->'time' desc")).offset(10).first
    demoted.update! data: demoted.data.merge('score' => 1), updated_at: stamp

    get '/', {}, 'HTTP_IF_NONE_MATCH' => before

    assert_equal 200, last_response.status, 'membership changed, must not 304'
  end

  # --- listing scope --------------------------------------------------------

  # The listing used to rely on comments never carrying a score key.
  def test_homepage_lists_only_stories
    create_item id: 1, title: 'Real story', score: 100
    create_item id: 2, type: 'comment', text: 'not a story', score: 500

    get '/'

    assert_includes last_response.body, 'Real story'
    refute_includes last_response.body, 'not a story'
  end
end
