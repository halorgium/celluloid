require 'rubygems'
require 'bundler/setup'
require 'celluloid/autostart'
require 'celluloid/rspec'
require 'coveralls'
Coveralls.wear!

Thread.abort_on_exception = true

logfile = File.open(File.expand_path("../../log/test.log", __FILE__), 'a')
logfile.sync = true
Celluloid.logger = Logger.new(logfile)
Celluloid.shutdown_timeout = 1

Dir['./spec/support/*.rb'].map {|f| require f }

require 'pry'

RSpec.configure do |config|
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
  config.mock_with :nothing

  config.around(:each) do |example|
    full_description = example.metadata[:full_description]
    Celluloid.logger.info "example: #{full_description.inspect}"
    ignored = [
    ]
    case full_description
    when *ignored
      Celluloid.logger.info "ignoring"
    else
      Celluloid.logger.info "cleaning up"
      Celluloid.shutdown
      Celluloid.boot
      Celluloid.logger.info "running"
      mutex = Mutex.new
      condition = ConditionVariable.new
      $spec_thread = Thread.new {
        mutex.synchronize {
          begin
            Celluloid.logger.info "before example"
            example.run
            Celluloid.logger.info "after example"
          rescue Exception => ex
            Celluloid.logger.crash ex, "Got an exception with spec thread"
          end
          condition.signal
        }
      }
      mutex.synchronize {
        condition.wait(mutex, 1)
        if $spec_thread.alive?
          $stderr.print "spec thread is still alive, killing\n"
          $spec_thread.kill
        end
      }
      Celluloid.logger.info "finished"
    end
  end
end

r, w = IO.pipe

Thread.new {
  thread = nil
  while r.read(1)
    if thread && thread.alive?
      $stderr.print "killing existing INFO thread\n"
      thread.kill
    end
    thread = Thread.new {
      Celluloid.dump
      binding.pry
    }
  end
}

trap("INFO") {
  $stderr.print "got INFO signal\n"
  w.write "."
}
