require 'integration_helper'

class Callbacks
  def worker1 status, opts
    Sidekiq.logger.info "11111111111111111111111 #{status.data}"

    overall = Sidekiq::Batch.new status.parent_bid
    overall.jobs do
      batch = Sidekiq::Batch.new
      batch.on(:success, "Callbacks#worker2")
      batch.jobs do
        2.times { Worker2.perform_async }
      end
    end
  end

  def worker2 status, opts
    Sidekiq.logger.info "22222222222222222222222 #{status.data}"
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
    Sidekiq.logger.info "333333333333333333333333 #{status.data}"
  end

end

class Worker1
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work1"
  end
end

class Worker2
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work 2"
    if bid
      batch.jobs do
        10.times { Worker3.perform_async }
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

class MyCallback
  def on_success(status, options)
    Sidekiq.logger.info "Success $$$$$$$$$$$ #{options} #{status.data}"
  end
  alias_method :multi, :on_success

  def on_complete(status, options)
    Sidekiq.logger.info "Complete #{options} #{status.data}"
  end
end

def dump_redis_keys
  keys = Sidekiq.redis { |r| r.keys('BID-*') }
  puts keys.inspect
end

overall = Sidekiq::Batch.new
overall.on(:success, MyCallback, to: 'success@gmail.com')
overall.jobs do
  batch1 = Sidekiq::Batch.new
  batch1.on(:success, "Callbacks#worker1")
  batch1.jobs do
    Worker1.perform_async
  end
end

dump_redis_keys

puts Sidekiq::Worker.jobs

Sidekiq::Worker.drain_all

dump_redis_keys