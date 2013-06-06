require 'timers'

module Celluloid
  # Don't do Actor-like things outside Actor scope
  class NotActorError < Celluloid::Error; end

  # Trying to do something to a dead actor
  class DeadActorError < Celluloid::Error; end

  # A timeout occured before the given request could complete
  class TimeoutError < Celluloid::Error; end

  # The sender made an error, not the current actor
  class AbortError < Celluloid::Error
    attr_reader :cause

    def initialize(cause)
      @cause = cause
      super "caused by #{cause.inspect}: #{cause.to_s}"
    end
  end

  LINKING_TIMEOUT = 5 # linking times out after 5 seconds

  # Actors are Celluloid's concurrency primitive. They're implemented as
  # normal Ruby objects wrapped in threads which communicate with asynchronous
  # messages.

  class Actor
    attr_reader :proxy, :tasks, :links, :mailbox, :thread, :name, :locals

    class << self
      extend Forwardable

      def_delegators "Celluloid::Registry.root", :[], :[]=

      def registered
        Registry.root.names
      end

      def clear_registry
        Registry.root.clear
      end

      # Obtain the current actor
      def current
        actor = Thread.current[:celluloid_actor]
        raise NotActorError, "not in actor scope" unless actor
        actor.proxy
      end

      # Obtain the name of the current actor
      def name
        actor = Thread.current[:celluloid_actor]
        raise NotActorError, "not in actor scope" unless actor
        actor.name
      end

      # Invoke a method on the given actor via its mailbox
      def call(mailbox, meth, *args, &block)
        proxy = SyncProxy.new(mailbox, "UnknownClass")
        proxy.method_missing(meth, *args, &block)
      end

      # Invoke a method asynchronously on an actor via its mailbox
      def async(mailbox, meth, *args, &block)
        proxy = AsyncProxy.new(mailbox, "UnknownClass")
        proxy.method_missing(meth, *args, &block)
      end

      # Call a method asynchronously and retrieve its value later
      def future(mailbox, meth, *args, &block)
        proxy = FutureProxy.new(mailbox, "UnknownClass")
        proxy.method_missing(meth, *args, &block)
      end

      # Obtain all running actors in the system
      def all
        actors = []
        Thread.list.each do |t|
          next unless t.celluloid? && t.role == :actor
          actors << t.actor.proxy if t.actor && t.actor.respond_to?(:proxy)
        end
        actors
      end

      # Watch for exit events from another actor
      def monitor(actor)
        raise NotActorError, "can't link outside actor context" unless Celluloid.actor?
        Thread.current[:celluloid_actor].linking_request(actor, :link)
      end

      # Stop waiting for exit events from another actor
      def unmonitor(actor)
        raise NotActorError, "can't link outside actor context" unless Celluloid.actor?
        Thread.current[:celluloid_actor].linking_request(actor, :unlink)
      end

      # Link to another actor
      def link(actor)
        monitor actor
        Thread.current[:celluloid_actor].links << actor
      end

      # Unlink from another actor
      def unlink(actor)
        unmonitor actor
        Thread.current[:celluloid_actor].links.delete actor
      end

      # Are we monitoring the given actor?
      def monitoring?(actor)
        actor.links.include? Actor.current
      end

      # Are we bidirectionally linked to the given actor?
      def linked_to?(actor)
        monitoring?(actor) && Thread.current[:celluloid_actor].links.include?(actor)
      end

      # Forcibly kill a given actor
      def kill(actor)
        actor.thread.kill
        actor.mailbox.shutdown
      end

      # Wait for an actor to terminate
      def join(actor, timeout = nil)
        actor.thread.join(timeout)
        actor
      end
    end

    def initialize(options = {})
      @behavior     = options[:behavior]
      @mailbox      = options[:mailbox] || Mailbox.new
      @task_class   = options[:task_class] || Celluloid.task_class

      @tasks     = TaskSet.new
      @links     = Links.new
      @signals   = Signals.new
      @receivers = Receivers.new
      @timers    = Timers.new
      @handlers  = Handlers.new
      @running   = false
      @exclusive = false
      @name      = nil
      @locals    = {}

      handle(SystemEvent) do |message|
        handle_system_event message
      end
    end

    def start
      @running = true
      @thread = ThreadHandle.new(:actor) do
        setup_thread
        run
      end

      @proxy = ActorProxy.new(@thread, @mailbox)
    end

    def setup_thread
      Thread.current[:celluloid_actor]   = self
      Thread.current[:celluloid_mailbox] = @mailbox
    end

    # Run the actor loop
    def run
      begin
        while @running
          if message = @mailbox.receive(timeout_interval)
            handle_message message
          else
            # No message indicates a timeout
            @timers.fire
            @receivers.fire_timers
          end
        end
      rescue MailboxShutdown
        # If the mailbox detects shutdown, exit the actor
      end

      shutdown
    rescue Exception => ex
      handle_crash(ex)
      raise unless ex.is_a? StandardError
    end

    # Terminate this actor
    def terminate
      @running = false
    end

    # Is this actor running in exclusive mode?
    def exclusive?
      @exclusive
    end

    # Execute a code block in exclusive mode.
    def exclusive
      if @exclusive
        yield
      else
        begin
          @exclusive = true
          yield
        ensure
          @exclusive = false
        end
      end
    end

    # Perform a linking request with another actor
    def linking_request(receiver, type)
      exclusive do
        start_time = Time.now
        receiver.mailbox << LinkingRequest.new(Actor.current, type)
        system_events = []

        loop do
          wait_interval = start_time + LINKING_TIMEOUT - Time.now
          message = @mailbox.receive(wait_interval) do |msg|
            msg.is_a?(LinkingResponse) &&
            msg.actor.mailbox.address == receiver.mailbox.address &&
            msg.type == type
          end

          case message
          when LinkingResponse
            # We're done!
            system_events.each { |ev| handle_system_event(ev) }
            return
          when NilClass
            raise TimeoutError, "linking timeout of #{LINKING_TIMEOUT} seconds exceeded"
          when SystemEvent
            # Queue up pending system events to be processed after we've successfully linked
            system_events << message
          else raise 'wtf'
          end
        end
      end
    end

    # Send a signal with the given name to all waiting methods
    def signal(name, value = nil)
      @signals.broadcast name, value
    end

    # Wait for the given signal
    def wait(name)
      @signals.wait name
    end

    def handle(*patterns, &block)
      @handlers.handle(*patterns, &block)
    end

    # Receive an asynchronous message
    def receive(timeout = nil, &block)
      loop do
        message = @receivers.receive(timeout, &block)
        break message unless message.is_a?(SystemEvent)

        handle_system_event(message)
      end
    end

    # How long to wait until the next timer fires
    def timeout_interval
      i1 = @timers.wait_interval
      i2 = @receivers.wait_interval

      if i1 and i2
        i1 < i2 ? i1 : i2
      elsif i1
        i1
      else
        i2
      end
    end

    # Schedule a block to run at the given time
    def after(interval, &block)
      @timers.after(interval) { task(:timer, &block) }
    end

    # Schedule a block to run at the given time
    def every(interval, &block)
      @timers.every(interval) { task(:timer, &block) }
    end

    class Sleeper
      def initialize(timers, interval)
        @timers = timers
        @interval = interval
      end

      def before_suspend(task)
        @timers.after(@interval) { task.resume }
      end

      def wait
        Kernel.sleep(@interval)
      end
    end

    # Sleep for the given amount of time
    def sleep(interval)
      sleeper = Sleeper.new(@timers, interval)
      Celluloid.suspend(:sleeping, sleeper)
    end

    # Handle standard low-priority messages
    def handle_message(message)
      unless @handlers.handle_message(message)
        @receivers.handle_message(message)
      end
      message
    end

    # Handle high-priority system event messages
    def handle_system_event(event)
      case event
      when ExitEvent
        # TODO: @exit_handler is in CellActor
        task(:exit_handler) { handle_exit_event event }
      when LinkingRequest
        event.process(links)
      when NamingRequest
        @name = event.name
      when TerminationRequest
        terminate
      when SignalConditionRequest
        event.call
      end
    end

    # Handle exit events received by this actor
    def handle_exit_event(event)
      @links.delete event.actor
      Logger.info "handling exit event: #{event.inspect}"

      return @behavior.handle_exit_event(event) if @behavior.handling_exit_events?

      # Reraise exceptions from linked actors
      # If no reason is given, actor terminated cleanly
      raise event.reason if event.reason
    end

    # Handle any exceptions that occur within a running actor
    def handle_crash(exception)
      # TODO: add meta info
      Logger.crash("Actor crashed!", exception)
      shutdown ExitEvent.new(@proxy, exception)
    rescue => ex
      Logger.crash("ERROR HANDLER CRASHED!", ex)
    end

    # Handle cleaning up this actor after it exits
    def shutdown(exit_event = ExitEvent.new(@proxy))
      @behavior.shutdown
      cleanup exit_event
    ensure
      Thread.current[:celluloid_actor]   = nil
      Thread.current[:celluloid_mailbox] = nil
    end

    # Clean up after this actor
    def cleanup(exit_event)
      @mailbox.shutdown
      @links.each do |actor|
        if actor.mailbox.alive?
          actor.mailbox << exit_event
        end
      end

      tasks.each { |task| task.terminate }
    rescue => ex
      # TODO: metadata
      Logger.crash("CLEANUP CRASHED!", ex)
    end

    # Run a method inside a task unless it's exclusive
    def task(task_type, &block)
      @task_class.new(task_type, &block).resume
    end
  end
end
