module Celluloid
  # A proxy which sends synchronous calls to an actor
  class SyncProxy < AbstractProxy
    attr_reader :mailbox

    def initialize(mailbox, klass, uuid)
      @mailbox, @klass, @uuid = mailbox, klass, uuid
    end

    def inspect
      "#<Celluloid::SyncProxy(#{@klass})>"
    end

    def method_missing(meth, *args, &block)
      unless @mailbox.alive?
        raise DeadActorError, "attempted to call a dead actor"
      end

      if @mailbox == ::Thread.current[:celluloid_mailbox]
        args.unshift meth
        meth = :__send__
      end

      call = SyncCall.new(::Celluloid.mailbox, uuid, meth, args, block)
      @mailbox << call
      call.value
    end
  end
end
