# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
require 'bundler/setup'
require 'minitest/autorun'

require './app'
Dir[File.expand_path 'lib/**/*.rb'].each { |f| require f }
