# frozen_string_literal: true

require './app'

# Fetches and caches Hacker News items
class Worker
  class FetchFailed < StandardError; end

  def self.interval
    value = Integer ENV.fetch('WORKER_INTERVAL', '300')
    raise ArgumentError, 'WORKER_INTERVAL must be positive' unless value.positive?

    value
  end

  def self.max_consecutive_failures
    Integer ENV.fetch('WORKER_MAX_FAILURES', '5')
  end

  def self.run
    App.logger.info 'Fetching top stories...'
    fetched = Item.top_stories
    if fetched.nil?
      App.logger.error 'Skipped finish: top stories fetch failed'
      raise FetchFailed, 'top story IDs unavailable'
    elsif fetched.empty?
      App.logger.error 'Done fetching top stories: none persisted'
      raise FetchFailed, 'no top stories persisted'
    else
      App.logger.info "Done fetching top stories (#{fetched.size})"
    end
  end

  def self.start
    failures = 0
    loop do
      begin
        run
        failures = 0
      rescue Interrupt, SignalException
        raise
      rescue StandardError => e
        failures += 1
        App.logger.error "Worker run failed (#{e.class}): #{e}\n#{Array(e.backtrace).join("\n")}"
        if failures >= max_consecutive_failures
          App.logger.fatal "Worker exiting after #{failures} consecutive failures"
          raise
        end
      end
      sleep interval
    end
  end
end

Worker.start if $PROGRAM_NAME == __FILE__
