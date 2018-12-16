require 'integration_helper'

class Worker1
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work1"
    batch = Sidekiq::Batch.new
    batch.on(:success, Worker2)
    batch.jobs do
      Worker2.perform_async
    end
  end
end

class Worker2
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work2"
    # batch = Sidekiq::Batch.new
    # batch.jobs do
    #   Worker3.perform_async
    # end
  end

  def on_success status, opts
    overall = Sidekiq::Batch.new status.parent_bid
    overall.jobs do
      batch = Sidekiq::Batch.new
      # batch.on(:success, "Callbacks#worker3")
      batch.jobs do
        Worker3.perform_async
      end
    end
  end
end

class Worker3
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work3"
  end
end


class SomeClass
  def on_complete(status, options)
    Sidekiq.logger.info "COMPLETE @@@@@@@@@@"
    Sidekiq.logger.info "Uh oh, batch has failures" if status.failures != 0
    Sidekiq.logger.info "Complete #{options} #{status.data}"
  end
  def on_success(status, options)
    Sidekiq.logger.info "#{options['uid']}'s batch succeeded.  Kudos!"
    Sidekiq.logger.info "Success #{options} #{status.data}"
  end
end
batch = Sidekiq::Batch.new
batch.on(:success, SomeClass, 'uid' => 3)
# You can also use Class#method notation
batch.on(:complete, SomeClass, 'uid' => 3)
batch.jobs do
  Worker1.perform_async
end

puts "Overall bid #{batch.bid}"

Sidekiq::Worker.drain_all
