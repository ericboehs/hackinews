# frozen_string_literal: true

require 'sinatra'
require './lib/hacker_news_api/client'

# The App
class App < Sinatra::Base
  get '/' do
    @top_stories = client.top_stories
    erb :index
  end

  private

  def client
    @client ||= HackerNewsApi::Client.new
  end
end
