module Celluloid
  # Calls represent requests to an actor
  class Call
    attr_reader :method, :arguments, :block

    def initialize(method, arguments = [], block = nil)
      @method, @arguments = method, arguments
      if block
        Scrolls.log(fn: "#{self.class}#initialize", at: "block-proxy")
        if Celluloid.exclusive?
          # FIXME: nicer exception
          raise "Cannot execute blocks on sender in exclusive mode"
        end
        @block = BlockProxy.new(self, Thread.mailbox, block)
      end
      Scrolls.log(fn: "#{self.class}#initialize", at: "start", method: @method.inspect, arguments: @arguments.inspect, block: @block.inspect)
    end

    def execute_block_on_receiver
      @block && @block.execution = :receiver
    end

    def dispatch(obj)
      _block = @block && @block.to_proc
      obj.public_send(@method, *@arguments, &_block)
    rescue NoMethodError => ex
      # Abort if the caller made a mistake
      raise AbortError.new(ex) unless obj.respond_to? @method

      # Otherwise something blew up. Crash this actor
      raise
    rescue ArgumentError => ex
      # Abort if the caller made a mistake
      begin
        arity = obj.method(@method).arity
      rescue NameError
        # In theory this shouldn't happen, but just in case
        raise AbortError.new(ex)
      end

      if arity >= 0
        raise AbortError.new(ex) if @arguments.size != arity
      elsif arity < -1
        mandatory_args = -arity - 1
        raise AbortError.new(ex) if arguments.size < mandatory_args
      end

      # Otherwise something blew up. Crash this actor
      raise
    end
  end

  # Synchronous calls wait for a response
  class SyncCall < Call
    attr_reader :caller, :task, :chain_id

    def initialize(caller, method, arguments = [], block = nil, task = Thread.current[:celluloid_task], chain_id = Thread.current[:celluloid_chain_id])
      super(method, arguments, block)

      @caller   = caller
      @task     = task
      @chain_id = chain_id || Celluloid.uuid
    end

    def dispatch(obj)
      Thread.current[:celluloid_chain_id] = @chain_id
      result = super(obj)
      respond SuccessResponse.new(self, result)
    rescue Exception => ex
      # Exceptions that occur during synchronous calls are reraised in the
      # context of the caller
      respond ErrorResponse.new(self, ex)

      # Aborting indicates a protocol error on the part of the caller
      # It should crash the caller, but the exception isn't reraised
      # Otherwise, it's a bug in this actor and should be reraised
      raise unless ex.is_a?(AbortError)
    ensure
      Thread.current[:celluloid_chain_id] = nil
    end

    def cleanup
      exception = DeadActorError.new("attempted to call a dead actor")
      respond ErrorResponse.new(self, exception)
    end

    def respond(message)
      @caller << message
    rescue MailboxError
      # It's possible the caller exited or crashed before we could send a
      # response to them.
    end
  end

  # Asynchronous calls don't wait for a response
  class AsyncCall < Call

    def dispatch(obj)
      Thread.current[:celluloid_chain_id] = Celluloid.uuid
      super(obj)
    rescue AbortError => ex
      # Swallow aborted async calls, as they indicate the caller made a mistake
      Logger.debug("#{obj.class}: async call `#@method` aborted!\n#{Logger.format_exception(ex.cause)}")
    ensure
      Thread.current[:celluloid_chain_id] = nil
    end

  end

  class BlockCall
    def initialize(call, caller, block, arguments, task = Thread.current[:celluloid_task])
      @call = call
      @caller = caller
      @block = block
      @arguments = arguments
      @task = task
      Scrolls.log(fn: "BlockCall#initialize", call: @call.__id__)
    end
    attr_reader :call, :task

    def dispatch
      Scrolls.log(fn: "BlockCall#dispatch", block: @block.inspect, arguments: @arguments)
      Scrolls.log(fn: "BlockCall#dispatch", call: @call.__id__, at: "before-call")
      response = @block.call(*@arguments)
      Scrolls.log(fn: "BlockCall#dispatch", call: @call.__id__, at: "after-call")
      @caller << BlockResponse.new(self, response)
      Scrolls.log(fn: "BlockCall#dispatch", call: @call.__id__, at: "after-reply")
    end
  end

end
