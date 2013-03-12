module Celluloid
  class BlockProxy
    def initialize(mailbox, block)
      @mailbox = mailbox
      @block = block
    end
    attr_writer :call

    #def call(*args)
    #  @block.call(*args)
    #end

    def to_proc
      Scrolls.log(fn: "BlockProxy#to_proc", at: "start")
      lambda do |*values|
        if task = Thread.current[:celluloid_task]
          @mailbox << BlockCall.new(@call, Actor.current.mailbox, @block, values)
          # TODO: if respond fails, the Task will never be resumed
          Scrolls.log(fn: "BlockProxy#to_proc.lambda", at: "after-respond", task: task.__id__)
          resp = task.suspend(:invokeblock)
          Scrolls.log(fn: "BlockProxy#to_proc.lambda", at: "after-suspend", resp: resp.class)
          resp
        else
          # TODO: this is calling the block "dangerously" in some random thread
          # usually this is inside Actor#receive or similar
          $stderr.puts "WARNING: block running outside of a Task"
          @block.call(*values)
        end
      end
    end
  end
end
