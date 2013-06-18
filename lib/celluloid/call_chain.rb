module Celluloid
  class CallChain
    def self.current_id=(value)
      Thread.current[:celluloid_chain_id] = value
      task = Thread.current[:celluloid_task]
      task.chain_id = value
    end

    def self.current_id
      Thread.current[:celluloid_chain_id]
    end
  end
 end
