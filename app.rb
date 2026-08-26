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
    @logger ||= Logger.new $stdout
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

  get '/stories/:id' do
    @story = Item.find params[:id]
    @title += " - #{@story.data['title']}"
    erb :story
  end
end

App.boot
