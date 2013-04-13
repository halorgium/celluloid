require 'rubygems'
require 'bundler/setup'
require 'celluloid/autostart'
require 'celluloid/rspec'
require 'coveralls'
Coveralls.wear!

logfile = File.open(File.expand_path("../../log/test.log", __FILE__), 'a')
logfile.sync = true
Celluloid.logger = Logger.new(logfile)
Celluloid.shutdown_timeout = 1
Celluloid.logger.formatter = Celluloid::Logger::FORMATTER

Dir['./spec/support/*.rb'].map {|f| require f }

RSpec.configure do |config|
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true

  config.before do |spec|
    Celluloid.shutdown
    Celluloid.boot

    metadata = spec.example.metadata
    message = "starting new example: #{metadata.fetch(:full_description) rescue nil}"
    Celluloid.logger.info message
    $stderr.puts message
    Celluloid.logger.info "*" * 80
  end
end
