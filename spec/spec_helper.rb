require 'rubygems'
require 'bundler/setup'
require 'celluloid'
require 'celluloid/rspec'
require 'coveralls'
Coveralls.wear!

logfile = File.open(File.expand_path("../../log/test.log", __FILE__), 'a')
logfile.sync = true

logger = Celluloid.logger = Logger.new(logfile)

Celluloid.shutdown_timeout = 1

Dir['./spec/support/*.rb'].map {|f| require f }

require 'pry-remote'

RSpec.configure do |config|
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true

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
      Celluloid.logger = logger
      Celluloid.shutdown
      sleep 0.01

      Celluloid.internal_pool.assert_inactive

      Celluloid.boot
      Celluloid.logger.info "running"
      mutex = Mutex.new
      condition = ConditionVariable.new
      $spec_thread = Thread.new {
        mutex.synchronize {
          begin
            $stderr.print "before example\n"
            example.run
            $stderr.print "after example\n"
          rescue Exception => ex
            $stderr.print "Got an exception with spec thread\n#{ex.inspect}\n#{ex.backtrace.join("\n")}"
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
      binding.remote_pry
    }
  end
}

trap("INFO") {
  $stderr.print "got INFO signal\n"
  w.write "."
}
