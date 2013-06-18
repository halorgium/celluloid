module Celluloid
  class ExclusiveTask < Task
    def initialize(type, meta)
      super

      @exclusive = true
    end

    def create(&block)
      @thread = Actor.current.thread
      @block = block
    end

    def resume
      @block.call
    end

    def backtrace
      @thread.backtrace
    end
  end
end
