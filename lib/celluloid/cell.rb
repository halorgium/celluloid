module Celluloid
  class Cell
    def initialize(behavior, options)
      @behavior = behavior
      @subject.instance_variable_set(OWNER_IVAR, @behavior)
      # TODO: support custom proxy class??
      @proxy = CellProxy.new(@behavior.actor_proxy, @behavior.mailbox, @subject.class.to_s, nil)

      @subject = options.fetch(:subject)
      @exclusives   = options[:exclusive_methods]
    end
  end
end
