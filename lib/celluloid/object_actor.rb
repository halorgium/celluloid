module Celluloid
  OWNER_IVAR = :@celluloid_owner # reference to owning actor

  # Wrap the given subject with an Actor
  class ObjectActor < Actor
    attr_reader :subject, :proxy

    def before_spawn(options)
      @subject      = options.fetch(:subject)
      @receiver_block_executions = options[:receiver_block_executions]

      handle(Call) do |message|
        task(:call, message.method) {
          if @receiver_block_executions && meth = message.method
            if meth == :__send__
              meth = message.arguments.first
            end
            if @receiver_block_executions.include?(meth.to_sym)
              message.execute_block_on_receiver
            end
          end
          message.dispatch(@subject)
        }
      end
      handle(BlockCall) do |message|
        task(:invoke_block) { message.dispatch }
      end
      handle(BlockResponse, Response) do |message|
        message.dispatch
      end
    end

    def after_spawn(options)
      @proxy = (options[:proxy_class] || ActorProxy).new(self)
      @subject.instance_variable_set(OWNER_IVAR, self)
    end
  end
end
