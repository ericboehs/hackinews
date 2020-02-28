# frozen_string_literal: true

require 'sinatra'

# The App
class App < Sinatra::Base
  get '/' do
    erb :index
  end
end
