# frozen_string_literal: true

require './app'

# Fetches and caches Hacker News items
class Worker
  INTERVAL = Integer(ENV.fetch('WORKER_INTERVAL', '300'))

  def self.run
    App.logger.info 'Fetching top stories...'
    Item.top_stories
    App.logger.info 'Done fetching top stories'
  end

  def self.start
    loop do
      run
      sleep INTERVAL
    end
  end
end

Worker.start if $PROGRAM_NAME == __FILE__
