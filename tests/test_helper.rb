# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/pride'

require './app'
