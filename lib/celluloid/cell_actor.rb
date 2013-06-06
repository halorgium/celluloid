module Celluloid
  # Wrap the given subject with an Actor
  class CellActor
    def initialize(options)
      @cell         = Cell.new(options.merge(:behavior => self))
      @actor        = Actor.new(options.merge(:behavior => self))

      setup(options)

      @actor.start
      @cell.after_spawn(@actor.proxy, @actor.mailbox)
    end

    def setup(options)
      @exit_handler = options[:exit_handler]

      handle(Call) do |message|
        @cell.invoke(message)
      end
      handle(BlockCall) do |message|
        task(:invoke_block) { message.dispatch }
      end
      handle(BlockResponse, Response) do |message|
        message.dispatch
      end
    end

    def proxy
      @cell.proxy
    end

    def handle_exit_event(event)
      @cell.handle_exit_event(event, @exit_handler)
    end

    def handling_exit_events?
      @exit_handler
    end

    # Run the user-defined finalizer, if one is set
    def shutdown
      @cell.shutdown
    end

    # SUPER

    def actor_proxy
      @actor.proxy
    end

    def handle(*patterns, &block)
      @actor.handle(*patterns, &block)
    end

    def task(task_type, exclusively, &block)
      if exclusively
        exclusive { block.call }
      else
        @actor.task(task_type, &block)
      end
    end
  end
end
