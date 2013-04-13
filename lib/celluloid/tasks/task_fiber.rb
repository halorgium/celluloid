module Celluloid
  class FiberStackError < Celluloid::Error; end

  # Tasks with a Fiber backend
  class TaskFiber < Task

    def create
      uuid = Celluloid.uuid
      @fiber = Fiber.new do
        # FIXME: cannot use the writer as specs run inside normal Threads
        Thread.current[:celluloid_role] = :actor
        InternalPool.state Thread.current, "fiber: #{Fiber.current}: #{uuid}"
        yield
      end
    end

    def signal
      Fiber.yield
    end

    # Resume a suspended task, giving it a value to return if needed
    def deliver(value)
      @fiber.resume value
    rescue SystemStackError => ex
      raise FiberStackError, "#{ex} (please see https://github.com/celluloid/celluloid/wiki/Fiber-stack-errors)"
    rescue FiberError => ex
      raise DeadTaskError, "cannot resume a dead task (#{ex})"
    end

    # Terminate this task
    def terminate
      super
    rescue FiberError
      Logger.info "Got an error while terminating task: #{inspect} #{$!.inspect}"
      # If we're getting this the task should already be dead
    end
  end
end
