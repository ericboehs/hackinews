# frozen_string_literal: true

require './app'

# Fetches and caches Hacker News items
class Worker
  def self.interval
    value = Integer ENV.fetch('WORKER_INTERVAL', '300')
    raise ArgumentError, 'WORKER_INTERVAL must be positive' unless value.positive?

    value
  end

  def self.run
    App.logger.info 'Fetching top stories...'
    fetched = Item.top_stories
    if fetched
      App.logger.info 'Done fetching top stories'
    else
      App.logger.error 'Skipped finish: top stories fetch failed'
    end
  end

  def self.start
    loop do
      run
    rescue StandardError => e
      App.logger.error "Worker run failed (#{e.class}): #{e}"
    ensure
      sleep interval
    end
  end
end

Worker.start if $PROGRAM_NAME == __FILE__
