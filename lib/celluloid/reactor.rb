module Celluloid
  class Reactor
    def initialize(mailbox)
      @mailbox = mailbox
    end

    def register(thread)
      thread[:celluloid_reactor] = self
    end

    def wakeup
    end

    def run_once(timeout, &block)
      Celluloid.logger.info "running reactor once, timeout: #{timeout.inspect}"
      yield @mailbox.receive(timeout)
    end
  end
end
