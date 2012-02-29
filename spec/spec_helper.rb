
require File.expand_path('../../lib/directory_watcher', __FILE__)

require 'logging'
require 'rspec/logging_helper'
require 'rspec/autorun'
require 'scanner_scenarios'
require 'utility_classes'

include Logging.globally

#Thread.abort_on_exception = true

module DirectoryWatcherSpecs::Helpers
  def scratch_path( *parts )
    File.join( @scratch_dir, *parts )
  end

  # NOTE : touch will only work on *nix/BSD style systems
  # Touch the file with the given timestamp
  def touch( fname, time = Time.now )
    stamp = time.strftime("%Y%m%d%H%M.%S")
    %x[ touch -m -t #{stamp} #{fname} ]
  end

  def append_to( fname, count = 1 )
    File.open( fname, "a" ) { |f| count.times { f.puts Time.now }}
  end

  # create a unique list of numbers with size 'count' and from the range
  # 0..range
  def unique_integer_list( count, range )
    random = (0..range).to_a.sort_by { rand }
    return random[0,count]
  end
end

RSpec.configure do |config|
  config.before(:each) do
    @spec_dir = DirectoryWatcher.sub_path( "spec" )
    @scratch_dir = File.join(@spec_dir, "scratch")
    FileUtils.rm_rf @scratch_dir if File.directory?( @scratch_dir )
    FileUtils.mkdir @scratch_dir unless File.directory?( @scratch_dir )
  end

  config.after(:each) do
    FileUtils.rm_rf @scratch_dir if File.directory?(@scratch_dir)
  end

  config.include DirectoryWatcherSpecs::Helpers

  include RSpec::LoggingHelper
  config.capture_log_messages
end

RSpec::Matchers.define :be_events_like do |expected|
  match do |actual|
    a = actual.kind_of?( Array ) ?
            actual.map {|e| [ e.type, File.basename( e.path ) ]} :
            [ actual.type, File.basename( actual.path ) ]
    a == expected
  end

  failure_message_for_should do |actual|
    s = StringIO.new
    s.puts [ "Actual".ljust(20), "Expected".ljust(20), "Same?".ljust(20) ].join(" ")
    s.puts [ "-"*20, "-"*20, "-"*20 ].join(" ")
    [ actual.size, expected.size ].max.times do |x|
      a = actual[x]
      a = a.kind_of?( Array ) ?
              a.map {|e| [ e.type, File.basename( e.path ) ]} :
              [ a.type, File.basename( a.path ) ]
      e = expected[x]
      r = (a == e) ? "OK" : "Differ"
      s.puts [ a.inspect.ljust(20), e.inspect.ljust(20), r ].join(" ")
    end
    s.string
  end
end
