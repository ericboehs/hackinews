# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'tests'
  t.test_files = FileList['tests/**/*_test.rb']
  t.warning = false
end

task default: :test

desc 'Fetch top stories once'
task :worker do
  require_relative 'worker'
  Worker.run
end
