#
# = directory_watcher.rb
#
# See DirectoryWatcher for detailed documentation and usage.
#

require 'set'
require 'thread'
require 'yaml'

require 'directory_watcher/paths'
require 'directory_watcher/version'
require 'directory_watcher/configuration'
require 'directory_watcher/logable'

# == Synopsis
#
# A class for watching files within a directory and generating events when
# those files change.
#
# == Details
#
# A directory watcher is an +Observable+ object that sends events to
# registered observers when file changes are detected within the directory
# being watched.
#
# The directory watcher operates by scanning the directory at some interval
# and creating a list of the files it finds. File events are detected by
# comparing the current file list with the file list from the previous scan
# interval. Three types of events are supported -- *added*, *modified*, and
# *removed*.
#
# An added event is generated when the file appears in the current file
# list but not in the previous scan interval file list. A removed event is
# generated when the file appears in the previous scan interval file list
# but not in the current file list. A modified event is generated when the
# file appears in the current and the previous interval file list, but the
# file modification time or the file size differs between the two lists.
#
# The file events are collected into an array, and all registered observers
# receive all file events for each scan interval. It is up to the individual
# observers to filter the events they are interested in.
#
# === File Selection
#
# The directory watcher uses glob patterns to select the files to scan. The
# default glob pattern will select all regular files in the directory of
# interest '*'.
#
# Here are a few useful glob examples:
#
#     '*'               => all files in the current directory
#     '**/*'            => all files in all subdirectories
#     '**/*.rb'         => all ruby files
#     'ext/**/*.{h,c}'  => all C source code files
#
# *Note*: file events will never be generated for directories. Only regular
# files are included in the file scan.
#
# === Stable Files
#
# A fourth file event is supported but not enabled by default -- the
# *stable* event. This event is generated after a file has been added or
# modified and then remains unchanged for a certain number of scan
# intervals.
#
# To enable the generation of this event the +stable+ count must be
# configured. This is the number of scan intervals a file must remain
# unchanged (based modification time and file size) before it is considered
# stable.
#
# To disable this event the +stable+ count should be set to +nil+.
#
# == Usage
#
# Learn by Doing -- here are a few different ways to configure and use a
# directory watcher.
#
# === Basic
#
# This basic recipe will watch all files in the current directory and
# generate the three default events. We'll register an observer that simply
# prints the events to standard out.
#
#    require 'directory_watcher'
#
#    dw = DirectoryWatcher.new '.'
#    dw.add_observer {|*args| args.each {|event| puts event}}
#
#    dw.start
#    gets      # when the user hits "enter" the script will terminate
#    dw.stop
#
# === Suppress Initial "added" Events
#
# This little twist will suppress the initial "added" events that are
# generated the first time the directory is scanned. This is done by
# pre-loading the watcher with files -- i.e. telling the watcher to scan for
# files before actually starting the scan loop.
#
#    require 'directory_watcher'
#
#    dw = DirectoryWatcher.new '.', :pre_load => true
#    dw.glob = '**/*.rb'
#    dw.add_observer {|*args| args.each {|event| puts event}}
#
#    dw.start
#    gets      # when the user hits "enter" the script will terminate
#    dw.stop
#
# There is one catch with this recipe. The glob pattern must be specified
# before the pre-load takes place. The glob pattern can be given as an
# option to the constructor:
#
#    dw = DirectoryWatcher.new '.', :glob => '**/*.rb', :pre_load => true
#
# The other option is to use the reset method:
#
#    dw = DirectoryWatcher.new '.'
#    dw.glob = '**/*.rb'
#    dw.reset true     # the +true+ flag causes the watcher to pre-load
#                      # the files
#
# === Generate "stable" Events
#
# In order to generate stable events, the stable count must be specified. In
# this example the interval is set to 5.0 seconds and the stable count is
# set to 2. Stable events will only be generated for files after they have
# remain unchanged for 10 seconds (5.0 * 2).
#
#    require 'directory_watcher'
#
#    dw = DirectoryWatcher.new '.', :glob => '**/*.rb'
#    dw.interval = 5.0
#    dw.stable = 2
#    dw.add_observer {|*args| args.each {|event| puts event}}
#
#    dw.start
#    gets      # when the user hits "enter" the script will terminate
#    dw.stop
#
# === Persisting State
#
# A directory watcher can be configured to persist its current state to a
# file when it is stopped and to load state from that same file when it
# starts. Setting the +persist+ value to a filename will enable this
# feature.
#
#    require 'directory_watcher'
#
#    dw = DirectoryWatcher.new '.', :glob => '**/*.rb'
#    dw.interval = 5.0
#    dw.persist = "dw_state.yml"
#    dw.add_observer {|*args| args.each {|event| puts event}}
#
#    dw.start  # loads state from dw_state.yml
#    gets      # when the user hits "enter" the script will terminate
#    dw.stop   # stores state to dw_state.yml
#
# === Running Once
#
# Instead of using the built in run loop, the directory watcher can be run
# one or many times using the +run_once+ method. The state of the directory
# watcher can be loaded and dumped if so desired.
#
#    dw = DirectoryWatcher.new '.', :glob => '**/*.rb'
#    dw.persist = "dw_state.yml"
#    dw.add_observer {|*args| args.each {|event| puts event}}
#
#    dw.load!       # loads state from dw_state.yml
#    dw.run_once
#    sleep 5.0
#    dw.run_once
#    dw.persist!    # stores state to dw_state.yml
#
# === Ordering of Events
#
# In the case, particularly in the initial scan, or in cases where the Scanner
# may be doing a large pass over the monitored locations, many events may be
# generated all at once. In the default case, these will be emitted in the order
# in which they are observed, which tends to be alphabetical, but it not
# guaranteed. If you wish the events to be order by modified time, or file size
# this may be done by setting the +sort_by+ and/or the +order_by+ options.
#
#    dw = DirectoryWatcher.new '.', :glob => '**/*.rb', :sort_by => :mtime
#    dw.add_observer {|*args| args.each {|event| puts event}}
#    dw.start
#    gets      # when the user hits "enter" the script will terminate
#    dw.stop
#
# === Scanning Strategies
#
# By default DirectoryWatcher uses a thread that scans the directory being
# watched for files and calls "stat" on each file. The stat information is
# used to determine which files have been modified, added, removed, etc.
# This approach is fairly intensive for short intervals and/or directories
# with many files.
#
# DirectoryWatcher supports using Cool.io, EventMachine, or Rev instead
# of a busy polling thread. These libraries use system level kernel hooks to
# receive notifications of file system changes. This makes DirectoryWorker
# much more efficient.
#
# This example will use Cool.io to generate file notifications.
#
#    dw = DirectoryWatcher.new '.', :glob => '**/*.rb', :scanner => :coolio
#    dw.add_observer {|*args| args.each {|event| puts event}}
#
#    dw.start
#    gets      # when the user hits "enter" the script will terminate
#    dw.stop
#
# The scanner cannot be changed after the DirectoryWatcher has been
# created. To use an EventMachine scanner, pass :em as the :scanner
# option.
#
# If you wish to use the Cool.io scanner, then you must have the Cool.io gem
# installed. The same goes for EventMachine and Rev. To install any of these
# gems run the following on the command line:
#
#   gem install cool.io
#   gem install eventmachine
#   gem install rev
#
# Note: Rev has been replace by Cool.io and support for the Rev scanner will
# eventually be dropped from DirectoryWatcher.
#
# == Contact
#
# A lot of discussion happens about Ruby in general on the ruby-talk
# mailing list (http://www.ruby-lang.org/en/ml.html), and you can ask
# any questions you might have there. I monitor the list, as do many
# other helpful Rubyists, and you're sure to get a quick answer. Of
# course, you're also welcome to email me (Tim Pease) directly at the
# at tim.pease@gmail.com, and I'll do my best to help you out.
#
# (the above paragraph was blatantly stolen from Nathaniel Talbott's
# Test::Unit documentation)
#
# == Author
#
# Tim Pease
#
class DirectoryWatcher
  extend Paths
  extend Version
  include Logable

  # access the configuration of the DirectoryWatcher
  attr_reader :config

  # call-seq:
  #    DirectoryWatcher.new( directory, options )
  #
  # Create a new +DirectoryWatcher+ that will generate events when file
  # changes are detected in the given _directory_. If the _directory_ does
  # not exist, it will be created. The following options can be passed to
  # this method:
  #
  #    :glob      =>  '*'      file glob pattern to restrict scanning
  #    :interval  =>  30.0     the directory scan interval (in seconds)
  #    :stable    =>  nil      the number of intervals a file must remain
  #                            unchanged for it to be considered "stable"
  #    :pre_load  =>  false    setting this option to true will pre-load the
  #                            file list effectively skipping the initial
  #                            round of file added events that would normally
  #                            be generated (glob pattern must also be
  #                            specified otherwise odd things will happen)
  #    :persist   =>  file     the state will be persisted to and restored
  #                            from the file when the directory watcher is
  #                            stopped and started (respectively)
  #    :scanner   =>  nil      the directory scanning strategy to use with
  #                            the directory watcher (either :coolio, :em, :rev or nil)
  #    :sort_by   =>  :path    the sort order of the scans, when there are
  #                            multiple events ready for deliver. This can be
  #                            one of:
  #
  #                               :path  => default, order by file name
  #                               :mtime => order by last modified time
  #                               :size  => order by file size
  #   :order_by   => :ascending The direction in which the sorted items are
  #                             sorted. Either :ascending or :descending
  #   :logger     => nil      An object that responds to the debug, info, warn,
  #                           error and fatal methods. Using the default will
  #                           use Logging gem if it is available and then fall
  #                           back to NullLogger
  #
  # The default glob pattern will scan all files in the configured directory.
  # Setting the :stable option to +nil+ will prevent stable events from being
  # generated.
  #
  # Additional information about the available options is documented in the
  # Configuration class.
  #
  def initialize( directory, opts = {} )
    @observer_peers = {}
    @config = Configuration.new( opts.merge( :dir => directory ) )

    setup_dir(config.dir)

    @notifier = Notifier.new(config, @observer_peers)
    @collector = Collector.new(config)
    @scanner = config.scanner_class.new(config)
  end

  # Setup the directory existence.
  #
  # Raise an error if the item passed in does exist but is not a directory
  #
  # Returns nothing
  def setup_dir( dir )
    if Kernel.test(?e, dir)
      unless Kernel.test(?d, dir)
        raise ArgumentError, "'#{dir}' is not a directory"
      end
    else
      Dir.mkdir dir
    end
  end

  # call-seq:
  #    add_observer( observer, func = :update )
  #    add_observer {|*events| block}
  #
  # Adds the given _observer_ as an observer on this directory watcher. The
  # _observer_ will now receive file events when they are generated. The
  # second optional argument specifies a method to notify updates, of which
  # the default value is +update+.
  #
  # Optionally, a block can be passed as the observer. The block will be
  # executed with the file events passed as the arguments. A reference to the
  # underlying +Proc+ object will be returned for use with the
  # +delete_observer+ method.
  #
  def add_observer( observer = nil, func = :update, &block )
    unless block.nil?
      observer = block.to_proc
      func = :call
    end

    unless observer.respond_to? func
      raise NoMethodError, "observer does not respond to `#{func.to_s}'"
    end

    logger.debug "Added observer"
    @observer_peers[observer] = func
    observer
  end

  # Delete +observer+ as an observer of this directory watcher. It will no
  # longer receive notifications.
  #
  def delete_observer( observer )
    @observer_peers.delete observer
  end

  # Delete all observers associated with the directory watcher.
  #
  def delete_observers
    @observer_peers.clear
  end

  # Return the number of observers associated with this directory watcher..
  #
  def count_observers
    @observer_peers.size
  end

  # call-seq:
  #    glob = '*'
  #    glob = ['lib/**/*.rb', 'test/**/*.rb']
  #
  # Sets the glob pattern that will be used when scanning the directory for
  # files. A single glob pattern can be given or an array of glob patterns.
  #
  def glob=( val )
    config.glob = val
  end

  def glob
    config.glob
  end

  # Sets the directory scan interval. The directory will be scanned every
  # _interval_ seconds for changes to files matching the glob pattern.
  # Raises +ArgumentError+ if the interval is zero or negative.
  #
  def interval=( val )
    config.interval = val
  end

  def interval
    config.interval
  end

  # Sets the number of intervals a file must remain unchanged before it is
  # considered "stable". When this condition is met, a stable event is
  # generated for the file. If stable is set to +nil+ then stable events
  # will not be generated.
  #
  # A stable event will be generated once for a file. Another stable event
  # will only be generated after the file has been modified and then remains
  # unchanged for _stable_ intervals.
  #
  # Example:
  #
  #     dw = DirectoryWatcher.new( '/tmp', :glob => 'swap.*' )
  #     dw.interval = 15.0
  #     dw.stable = 4
  #
  # In this example, a directory watcher is configured to look for swap files
  # in the /tmp directory. Stable events will be generated every 4 scan
  # intervals iff a swap remains unchanged for that time. In this case the
  # time is 60 seconds (15.0 * 4).
  #
  def stable=( val )
    config.stable = val
  end

  def stable
    config.stable
  end

  # Sets the name of the file to which the directory watcher state will be
  # persisted when it is stopped. Setting the persist filename to +nil+ will
  # disable this feature.
  #
  def persist=( filename )
    config.persist = filename
  end

  def persist
    config.persist
  end

  # Write the current state of the directory watcher to the persist file.
  # This method will do nothing if the directory watcher is running or if
  # the persist file is not configured.
  #
  def persist!
    return if running?
    File.open(persist, 'w') { |fd| @collector.dump_stats(fd) } if persist?
    self
  rescue => e
    logger.error "Failure to write to persitence file #{persist.inspect} : #{e}"
  end

  # Is persistence done on this DirectoryWatcher
  #
  def persist?
    config.persist
  end

  # Loads the state of the directory watcher from the persist file. This
  # method will do nothing if the directory watcher is running or if the
  # persist file is not configured.
  #
  def load!
    return if running?
    File.open(persist, 'r') { |fd| @collector.load_stats(fd) } if persist? and test(?f, persist)
    self
  end

  # Returns +true+ if the directory watcher is currently running. Returns
  # +false+ if this is not the case.
  #
  def running?
    @scanner.running?
  end

  # Start the directory watcher scanning thread. If the directory watcher is
  # already running, this method will return without taking any action.
  #
  # Start returns one the scanner and the notifier say they are running
  #
  def start
    logger.debug "start (running -> #{running?})"
    return self if running?

    load!
    logger.debug "starting notifier #{@notifier.object_id}"
    @notifier.start
    Thread.pass until @notifier.running?

    logger.debug "starting collector"
    @collector.start
    Thread.pass until @collector.running?

    logger.debug "starting scanner"
    @scanner.start
    Thread.pass until @scanner.running?

    self
  end

  # Pauses the scanner.
  #
  def pause
    @scanner.pause
  end

  # Resume the emitting of events
  #
  def resume
    @scanner.resume
  end

  # Stop the directory watcher scanning thread. If the directory watcher is
  # already stopped, this method will return without taking any action.
  #
  # Stop returns once the scanner and notifier say they are no longer running
  def stop
    logger.debug "stop (running -> #{running?})"
    return self unless running?

    logger.debug"stopping scanner"
    @scanner.stop
    Thread.pass while @scanner.running?

    logger.debug"stopping collector"
    @collector.stop
    Thread.pass while @collector.running?

    logger.debug"stopping notifier"
    @notifier.stop
    Thread.pass while @notifier.running?

    self
  ensure
    persist!
  end

  # Sets the maximum number of scans the scanner is to make on the directory
  #
  def maximum_iterations=( value )
    @scanner.maximum_iterations = value
  end

  # Returns the maximum number of scans the directory scanner will perform
  #
  def maximum_iterations
    @scanner.maximum_iterations
  end

  # Returns the number of scans of the directory scanner it has
  # completed thus far.
  #
  # This will always report 0 unless a maximum number of scans has been set
  #
  def scans
    @scanner.iterations
  end

  # Returns true if the maximum number of scans has been reached.
  #
  def finished_scans?
    return true if maximum_iterations and (scans >= maximum_iterations)
    return false
  end

  # call-seq:
  #    reset( pre_load = false )
  #
  # Reset the directory watcher state by clearing the stored file list. If
  # the directory watcher is running, it will be stopped, the file list
  # cleared, and then restarted. Passing +true+ to this method will cause
  # the file list to be pre-loaded after it has been cleared effectively
  # skipping the initial round of file added events that would normally be
  # generated.
  #
  def reset( pre_load = false )
    was_running = @scanner.running?

    stop if was_running
    File.delete(config.persist) if persist? and test(?f, config.persist)
    @scanner.reset pre_load
    start if was_running
    self
  end

  # call-seq:
  #    join( limit = nil )
  #
  # If the directory watcher is running, the calling thread will suspend
  # execution and run the directory watcher thread. This method does not
  # return until the directory watcher is stopped or until _limit_ seconds
  # have passed.
  #
  # If the directory watcher is not running, this method returns immediately
  # with +nil+.
  #
  def join( limit = nil )
    @scanner.join limit
  end

  # Performs exactly one scan of the directory for file changes and notifies
  # the observers.
  #
  def run_once
    @scanner.run
    @collector.start unless running?
    @notifier.start unless running?
    self
  end
end  # class DirectoryWatcher

require 'directory_watcher/file_stat'
require 'directory_watcher/scan'
require 'directory_watcher/event'
require 'directory_watcher/threaded'
require 'directory_watcher/collector'
require 'directory_watcher/notifier'
require 'directory_watcher/scan_and_queue'
require 'directory_watcher/scanner'
require 'directory_watcher/eventable_scanner'
require 'directory_watcher/coolio_scanner'
require 'directory_watcher/em_scanner'
require 'directory_watcher/rev_scanner'

# EOF
