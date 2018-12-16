require 'integration_helper'

class AnotherWorker
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Another"
  end
end

class TestWorker
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Test Work"
    if bid
      batch.jobs do
        AnotherWorker.perform_async
      end
    end
  end
end

class MyCallback
  def on_success(status, options)
    Sidekiq.logger.info "Success #{options} #{status.data}"
  end
  alias_method :multi, :on_success

  def on_complete(status, options)
    Sidekiq.logger.info "Complete #{options} #{status.data}"
  end
end

batch = Sidekiq::Batch.new
batch.description = 'Test batch'
batch.callback_queue = :default
batch.on(:success, 'MyCallback#on_success', to: 'success@gmail.com')
batch.on(:success, 'MyCallback#multi', to: 'success@gmail.com')
batch.on(:complete, MyCallback, to: 'complete@gmail.com')

batch.jobs do
  10.times do
    Sidekiq.logger.info "Test"
    TestWorker.perform_async
  end
end
puts Sidekiq::Batch::Status.new(batch.bid).data

dump_redis_keys

puts Sidekiq::Worker.jobs

Sidekiq::Worker.drain_all

dump_redis_keys
