module Celluloid
  # A proxy which creates future calls to an actor
  class FutureProxy < AbstractProxy
    attr_reader :mailbox

    def initialize(mailbox, klass, uuid)
      @mailbox, @klass, @uuid = mailbox, klass, uuid
    end

    def inspect
      "#<Celluloid::FutureProxy(#{@klass})>"
    end

    def method_missing(meth, *args, &block)
      unless @mailbox.alive?
        raise DeadActorError, "attempted to call a dead actor"
      end

      if block_given?
        # FIXME: nicer exception
        raise "Cannot use blocks with futures yet"
      end

      future = Future.new
      call = SyncCall.new(future, uuid, meth, args, block)

      @mailbox << call

      future
    end
  end
end
