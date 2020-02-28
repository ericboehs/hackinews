# frozen_string_literal: true

require_relative '../test_helper'

module HackerNewsApi
  # Tests the hacker news api client
  class ClientTest < Minitest::Test
    def hacker_news_client
      @hacker_news_client ||= HackerNewsApi::Client.new
    end

    def top_story_ids
      @top_story_ids ||= hacker_news_client.top_story_ids
    end

    def story
      @story ||= hacker_news_client.story top_story_ids.last
    end

    def test_it_gets_top_story_ids
      assert top_story_ids.count > 100
      assert top_story_ids.first.is_a? Integer
    end

    def test_it_gets_a_story
      story[:score].is_a? Integer
    end

    def test_it_gets_top_stories
      hacker_news_client.top_stories
    end
  end
end
