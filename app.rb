# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'development'

require 'bundler/setup'
Bundler.require 'default', ENV.fetch('RACK_ENV')

require 'dotenv'
Dotenv.load '.env.local', '.env'

require 'logger'
require 'active_record'
require './models/item'

# The App
class App < Sinatra::Base
  MIN_SCORES = [0, 50, 100, 200, 300, 400, 500, 750, 1000].freeze

  configure :development do
    set :host_authorization, permitted_hosts: []
  end

  def self.boot
    url = ENV.fetch('DATABASE_URL') do
      abort 'DATABASE_URL is required. Copy .env.example to .env.local'
    end
    ActiveRecord::Base.establish_connection url
  end

  def self.logger
    @logger ||= Logger.new log_device
  end

  # The suite deliberately drives failure paths, and their warnings drown out
  # the output that actually signals a broken test. Set VERBOSE=1 to see them.
  def self.quiet_logs?
    ENV['RACK_ENV'] == 'test' && ENV['VERBOSE'].to_s.empty?
  end

  def self.log_device
    quiet_logs? ? IO::NULL : $stdout
  end

  # HN item text is HTML and is rendered raw by design. Everything else the API
  # gives us is attacker-influenced plain text and must be escaped.
  SAFE_URL_SCHEMES = %w[http https].freeze

  helpers do
    def h(value)
      Rack::Utils.escape_html value.to_s
    end

    # Escaping alone does not make an href safe: a javascript: url survives
    # escaping and still runs on click.
    def safe_url(value)
      uri = URI.parse value.to_s
      return '' unless SAFE_URL_SCHEMES.include?(uri.scheme)

      h uri.to_s
    rescue URI::InvalidURIError
      ''
    end

    # The cache only changes when the worker writes, so the newest row plus the
    # row count is a sound validator. Repeat requests then skip rendering
    # entirely, which matters most on the largest threads (~1.4 MB of HTML).
    def cache_for(records)
      cache_control :public, :must_revalidate, max_age: 30
      newest = records.filter_map(&:updated_at).max
      last_modified newest if newest
      etag "#{newest&.to_f}-#{records.size}"
    end
  end

  before do
    @title = 'HackiNews'
  end

  get '/' do
    @q = params['q']
    @min_score = (params['min_score'] || 50).to_i
    @next_min_score =
      MIN_SCORES[(MIN_SCORES.index(@min_score) || 0) + 1] || Float::INFINITY
    # .stories is what lets the partial index apply, and it stops the listing
    # depending on the accident that comments carry no score key.
    @stories = Item.stories.min_score(@min_score).by_time.limit 500
    @stories = @stories.title_matches @q if @q
    @stories = @stories.to_a
    cache_for @stories
    erb :index
  end

  # id is an int4 column, so anything outside its range cannot exist and would
  # otherwise blow up in the adapter rather than 404.
  STORY_ID_RANGE = (1..2_147_483_647)

  get '/stories/:id' do
    id = Integer(params[:id], exception: false)
    halt 404 unless id && STORY_ID_RANGE.cover?(id)

    # One query for the whole thread; every record shares the index, so
    # rendering nested replies issues no further queries.
    thread = Item.thread(id)
    @story = thread[id]
    unless @story
      @not_found_message = 'Story not found. It may have been pruned from the cache.'
      halt 404
    end

    cache_for thread.values
    @title += " - #{@story.data['title']}"
    erb :story
  end

  not_found do
    @title = 'HackiNews - Not Found'
    erb :not_found
  end
end

App.boot
