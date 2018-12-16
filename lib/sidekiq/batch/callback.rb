module Sidekiq
  class Batch
    module Callback

      class Finalize

        def dispatch status, opts
          bid = opts["bid"]
          callback_bid = status.bid
          event = opts["event"].to_sym
          callback_batch = bid != callback_bid

          Sidekiq.logger.debug {"Finalize #{event} batch id: #{opts["bid"]}, callback batch id: #{callback_bid} callback_batch #{callback_batch}"}

          batch_status = Status.new bid
          send(event, bid, batch_status, batch_status.parent_bid)

          if callback_batch
            # Different events are run in different batches
            Sidekiq::Batch.cleanup_redis callback_bid
          end
          Sidekiq::Batch.cleanup_redis bid if event == :success
        end

        def on_complete status, opts
          bid = status.bid
          Sidekiq.logger.debug {"Finalize complete batch id: #{opts["bid"]}, callback batch id: #{bid}"}

        end

        def success(bid, status, parent_bid)
          Sidekiq.logger.debug {"Update parent success #{parent_bid}"}
          if (parent_bid)
            _, _, success, pending, children = Sidekiq.redis do |r|
              r.multi do
                r.sadd("BID-#{parent_bid}-success", bid)
                r.expire("BID-#{parent_bid}-success", Sidekiq::Batch::BID_EXPIRE_TTL)
                r.scard("BID-#{parent_bid}-success")
                r.hincrby("BID-#{parent_bid}", "pending", 0)
                r.hincrby("BID-#{parent_bid}", "children", 0)
              end
            end

            Sidekiq.logger.debug {"Bid #{bid} parent #{parent_bid} pending #{pending} success #{success} children #{children}"}


            Batch.enqueue_callbacks(:success, parent_bid) if pending.to_i.zero? && children == success
          end
        end

        def complete(bid, status, parent_bid)
          Sidekiq.logger.debug {"Update parent complete #{parent_bid}"}

          if (parent_bid)
            _, complete, pending, children, failure = Sidekiq.redis do |r|
              r.multi do
                r.sadd("BID-#{parent_bid}-complete", bid)
                r.scard("BID-#{parent_bid}-complete")
                r.hincrby("BID-#{parent_bid}", "pending", 0)
                r.hincrby("BID-#{parent_bid}", "children", 0)
                r.hlen("BID-#{parent_bid}-failed")
              end
            end

            Batch.enqueue_callbacks(:complete, parent_bid) if complete == children && pending == failure
          end

          # TODO What is this doing?

          # pending, children, success = Sidekiq.redis do |r|
          #   r.multi do
          #     r.hincrby("BID-#{bid}", "pending", 0)
          #     r.hincrby("BID-#{bid}", "children", 0)
          #     r.scard("BID-#{bid}-success")
          #   end
          # end
          #
          # Batch.enqueue_callbacks(:success, bid) if pending.to_i.zero? && children == success

        end
        def cleanup_redis bid, callback_bid=nil
          Sidekiq::Batch.cleanup_redis bid
          Sidekiq::Batch.cleanup_redis callback_bid if callback_bid
        end
      end

      class NullWorker
        include Sidekiq::Worker
        def perform; end
      end

      class Worker
        include Sidekiq::Worker

        def perform(clazz, event, opts, bid, parent_bid)
          return unless %w(success complete).include?(event)
          clazz, method = clazz.split("#") if (clazz.class == String && clazz.include?("#"))
          method = "on_#{event}" if method.nil?
          status = Sidekiq::Batch::Status.new(bid)

          if object = Object.const_get(clazz)
            instance = object.new
            instance.send(method, status, opts) if instance.respond_to?(method)
          end
        end
      end
    end
  end
end
