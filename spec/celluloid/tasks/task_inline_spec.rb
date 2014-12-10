require 'spec_helper'

describe Celluloid::TaskInline, actor_system: :within do
  it_behaves_like "a Celluloid Task", Celluloid::TaskInline
end
