# frozen_string_literal: true

require './app'

# The Worker
class Worker
  def self.run
    Item.top_stories
    Item.remove_old_comments
  end
end
