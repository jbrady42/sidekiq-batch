require 'integration_helper'

class Callbacks
  def worker1 status, opts
    Sidekiq.logger.info "Success 1 #{status.data}"

    overall = Sidekiq::Batch.new status.parent_bid
    overall.jobs do
      batch = Sidekiq::Batch.new
      batch.on(:success, "Callbacks#worker2")
      batch.jobs do
        1.times { Worker2.perform_async }
      end
    end
  end

  def worker2 status, opts
    Sidekiq.logger.info "Success 2 #{status.data}"
    overall = Sidekiq::Batch.new status.parent_bid
    overall.jobs do
      batch = Sidekiq::Batch.new
      batch.on(:success, "Callbacks#worker3")
      batch.jobs do
        Worker3.perform_async
      end
    end

  end

  def worker3 status, opts
    Sidekiq.logger.info "Success 3 #{status.data}"
  end

end

class Worker1
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work1"
    batch = Sidekiq::Batch.new
    batch.on(:success, "Callbacks#worker2")
    batch.jobs do
      1.times { Worker3.perform_async }
    end
  end
end

class Worker2
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work 2"
    if bid
      batch.jobs do
        1.times { Worker3.perform_async }

      end
      newb = Sidekiq::Batch.new
      newb.jobs do
        1.times { Worker1.perform_async }
      end
      Sidekiq.logger.info Sidekiq::Batch::Status.new(newb.bid).data
      Sidekiq.logger.info Sidekiq::Batch::Status.new(bid).data

    end
  end
end

class Worker3
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work3"
  end
end

class MyCallback
  def on_success(status, options)
    Sidekiq.logger.info "!!!!!!!! Success Overall !!!!!!!! #{options} #{status.data}"
  end
  alias_method :multi, :on_success

  def on_complete(status, options)
    Sidekiq.logger.info "Complete #{options} #{status.data}"
  end
end

overall = Sidekiq::Batch.new
overall.on(:success, MyCallback, to: 'success@gmail.com')
overall.on(:complete, MyCallback, to: 'success@gmail.com')
overall.jobs do
  batch1 = Sidekiq::Batch.new
  batch1.on(:success, "Callbacks#worker1")
  batch1.jobs do
    Worker1.perform_async
  end
end

puts "Overall bid #{overall.bid}"

dump_redis_keys

puts Sidekiq::Worker.jobs

Sidekiq::Worker.drain_all

dump_redis_keys
