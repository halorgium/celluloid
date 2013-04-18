require 'celluloid/fiber'

class Thread
  attr_accessor :uuid_counter, :uuid_limit

  alias_method :old_set, :[]=

  def []=(key, value)
    Celluloid.logger.info "#{inspect} setting #{key.inspect} to #{value.class.inspect}"
    old_set(key, value)
  end
end
