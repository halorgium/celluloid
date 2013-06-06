require 'pry'
module Celluloid
  OWNER_IVAR = :@celluloid_owner # reference to owning actor

  # Don't do Cell-like things outside Cell scope
  class NotCellError < Celluloid::Error; end

  class Cell
    class << self
      # Obtain the current actor
      def current
        cell = Thread.current[:celluloid_cell]
        raise NotCellError, "not in cell scope" unless cell
        cell.proxy
      end
    end

    def initialize(options)
      @behavior                   = options[:behavior]
      @subject                    = options[:subject]
      @receiver_block_executions  = options[:receiver_block_executions]
      @exclusives                 = options[:exclusive_methods]

      # TODO: need to fix the leaked?
      @subject.instance_variable_set(OWNER_IVAR, @behavior)
    end
    attr_reader :proxy

    def after_spawn(actor_proxy, mailbox)
      # TODO: support custom proxy class
      @proxy = CellProxy.new(actor_proxy, mailbox, @subject.class.to_s)
    end

    def invoke(call)
      if @receiver_block_executions && meth = call.method
        if meth == :__send__
          meth = call.arguments.first
        end
        if @receiver_block_executions.include?(meth.to_sym)
          call.execute_block_on_receiver
        end
      end
      task(:call, call.method) {
        call.dispatch(@subject)
      }
    end

    def handle_exit_event(event, exit_handler)
      # Run the exit handler if available
      @subject.send(exit_handler, event.actor, event.reason)
    end

    def shutdown
      finalizer = @subject.class.finalizer
      if finalizer && @subject.respond_to?(finalizer, true)
        task(:finalizer, :finalize) { @subject.__send__(finalizer) }
      end
    rescue => ex
      Logger.crash("#{@subject.class}#finalize crashed!", ex)
    end

    def task(task_type, method_name)
      exclusively = @exclusives && (@exclusives == :all || (method_name && @exclusives.include?(method_name.to_sym)))
      @behavior.task(task_type, exclusively) do
        Thread.current[:celluloid_cell] = self
        yield
      end
    end
  end
end
