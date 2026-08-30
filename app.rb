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

  before do
    @title = 'HackiNews'
  end

  get '/' do
    @q = params['q']
    @min_score = (params['min_score'] || 50).to_i
    @next_min_score =
      MIN_SCORES[(MIN_SCORES.index(@min_score) || 0) + 1] || Float::INFINITY
    @stories = Item.min_score(@min_score).by_time.limit 500
    @stories = @stories.title_matches @q if @q
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
    @story = Item.thread(id)[id]
    unless @story
      @not_found_message = 'Story not found. It may have been pruned from the cache.'
      halt 404
    end

    @title += " - #{@story.data['title']}"
    erb :story
  end

  not_found do
    @title = 'HackiNews - Not Found'
    erb :not_found
  end
end

App.boot
