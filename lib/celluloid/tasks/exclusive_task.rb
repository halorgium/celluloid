module Celluloid
  class ExclusiveTask < Task
    def initialize(type, meta)
      super

      @exclusive = true
    end

    def create(&block)
      @block = block
    end

    def resume
      @block.call
    end
  end
end
