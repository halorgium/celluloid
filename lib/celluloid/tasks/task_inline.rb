module Celluloid
  class FiberStackError < Celluloid::Error; end

  # Tasks with a Fiber backend
  class TaskInline < Task
    def create
      @thread = Thread.current
      @started = false
      exclusive do
        yield
      end
    end

    def signal
      raise Error, "cannot suspend inline tasks"
    end

    def deliver(value)
      raise Error, "cannot resume inline tasks" if @started
      raise Error, "initial resume must not have a value: value=#{value.inspect}" unless value.nil?
      @started = true
    end

    def terminate
    end

    def backtrace
      @thread.backtrace
    end
  end
end
