require 'thread'

module Celluloid
  # Maintain a thread pool FOR SPEED!!
  class InternalPool
    @state_mutex = Mutex.new
    @state = {}
    def self.state(thread, state)
      @state_mutex.lock
      @state[thread] ||= []
      @state[thread] << state
    ensure
      @state_mutex.unlock rescue nil
      msg = if Thread.current == thread
              state
            else
              "%s: %s" % [state, thread.inspect]
            end
      Celluloid::Logger.debug msg
    end

    def self.state_data
      @state
    end

    attr_accessor :busy_size, :idle_size, :max_idle

    def initialize
      @pool = []
      @mutex = Mutex.new
      reset
    end

    def reset
      # TODO: should really adjust this based on usage
      @max_idle = 16
      @busy_size = @idle_size = 0
    end

    # Get a thread from the pool, running the given block
    def get(&block)
      @mutex.synchronize do
        begin
          if @pool.empty?
            thread = create
          else
            thread = @pool.shift
            @idle_size -= 1
          end
        end until thread.status # handle crashed threads

        @busy_size += 1
        InternalPool.state thread, "obtained thread: sending block"
        thread[:celluloid_queue] << block
        thread
      end
    end

    # Return a thread to the pool
    def put(thread)
      @mutex.synchronize do
        if @pool.size >= @max_idle
          InternalPool.state thread, "discarding"
          thread[:celluloid_queue] << nil
        else
          InternalPool.state thread, "reusing"
          thread.recycle
          @pool << thread
          @idle_size += 1
          @busy_size -= 1
        end
      end
    end

    # Create a new thread with an associated queue of procs to run
    def create
      queue = Queue.new
      thread = Thread.new do
        queue.pop
        InternalPool.state thread, "created"
        while proc = queue.pop
          begin
            InternalPool.state thread, "calling proc"
            proc.call
          rescue => ex
            Logger.crash("thread crashed", ex)
          end

          InternalPool.state thread, "back in queue"
          put thread
        end
        InternalPool.state thread, "death"
      end

      thread[:celluloid_queue] = queue
      queue << :start
      thread
    end

    def shutdown
      @mutex.synchronize do
        @max_idle = 0
        @pool.each do |thread|
          thread[:celluloid_queue] << nil
        end
      end
    end
  end

  self.internal_pool = InternalPool.new
end
