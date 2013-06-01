module Celluloid
  # A proxy which controls the Actor lifecycle
  class ActorProxy < AbstractProxy
    attr_reader :thread

    def initialize(thread, mailbox)
      @thread = thread
      @mailbox = mailbox
    end

    def inspect
      # TODO: use a system event to fetch actor state
      "#<Celluloid::Actor(#{@mailbox.uuid}) SOME USEFUL DATA>"
    rescue DeadActorError
      "#<Celluloid::Actor(#{@mailbox.uuid}) dead>"
    end

    def alive?
      @mailbox.alive?
    end

    # Terminate the associated actor
    def terminate
      terminate!
      Actor.join(self)
      nil
    end

    # Terminate the associated actor asynchronously
    def terminate!
      ::Kernel.raise DeadActorError, "actor already terminated" unless alive?
      @mailbox << TerminationRequest.new
    end
  end
end
