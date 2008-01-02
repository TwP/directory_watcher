#
# = directory_watcher.rb
#
# See DirectoryWatcher for detailed documentation and usage.
#

require 'observer'

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

  VERSION = '1.1.1'    # :nodoc:

  # An +Event+ structure contains the _type_ of the event and the file _path_
  # to which the event pertains. The type can be one of the following:
  #
  #    :added      =>  file has been added to the directory
  #    :modified   =>  file has been modified (either mtime or size or both
  #                    have changed)
  #    :removed    =>  file has been removed from the directory
  #    :stable     =>  file has stabilized since being added or modified
  #
  Event = Struct.new :type, :path

  # :stopdoc:
  class Event
    def to_s( ) "#{type} '#{path}'" end
  end
  # :startdoc:

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
  #
  # The default glob pattern will scan all files in the configured directory.
  # Setting the :stable option to +nil+ will prevent stable events from being
  # generated.
  #
  def initialize( directory, opts = {} )
    @dir = directory

    if Kernel.test(?e, @dir)
      unless Kernel.test(?d, @dir)
        raise ArgumentError, "'#{@dir}' is not a directory"
      end
    else
      Dir.create @dir
    end

    self.glob = opts[:glob] || '*'
    self.interval = opts[:interval] || 30
    self.stable = opts[:stable] || nil

    @files = (opts[:pre_load] ? scan_files : Hash.new)
    @events = []
    @thread = nil
    @observer_peers = {}
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
    @glob = case val
            when String; [File.join(@dir, val)]
            when Array; val.flatten.map! {|g| File.join(@dir, g)}
            else
              raise(ArgumentError,
                    'expecting a glob pattern or an array of glob patterns')
            end
    @glob.uniq!
    val
  end
  attr_reader :glob

  # call-seq:
  #    interval = 30.0
  #
  # Sets the directory scan interval. The directory will be scanned every
  # _interval_ seconds for changes to files matching the glob pattern.
  # Raises +ArgumentError+ if the interval is zero or negative.
  #
  def interval=( val )
    val = Float(val)
    raise ArgumentError, "interval must be greater than zero" if val <= 0
    @interval = Float(val)
  end
  attr_reader :interval

  # call-seq:
  #    stable = 2
  #
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
    if val.nil?
      @stable = nil
      return
    end

    val = Integer(val)
    raise ArgumentError, "stable must be greater than zero" if val <= 0
    @stable = val
  end
  attr_reader :stable

  # call-seq:
  #    running?
  #
  # Returns +true+ if the directory watcher is currently running. Returns
  # +false+ if this is not the case.
  #
  def running?
    !@thread.nil?
  end

  # call-seq:
  #    start
  #
  # Start the directory watcher scanning thread. If the directory watcher is
  # already running, this method will return without taking any action.
  #
  def start
    return if running?

    @stop = false
    @thread = Thread.new(self) {|dw| dw.__send__ :run}
    self
  end

  # call-seq:
  #    stop
  #
  # Stop the directory watcher scanning thread. If the directory watcher is
  # already stopped, this method will return without taking any action.
  #
  def stop
    return unless running?

    @stop = true
    @thread.wakeup if @thread.status == 'sleep'
    @thread.join
    @thread = nil
    self
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
    was_running = running?

    stop if was_running
    @files = (pre_load ? scan_files : Hash.new)
    start if was_running
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
    return unless running?
    @thread.join limit
  end


  private

  # call-seq:
  #    scan_files
  #
  # Using the configured glob pattern, scan the directory for all files and
  # return a hash with the filenames as keys and +File::Stat+ objects as the
  # values. The +File::Stat+ objects contain the mtime and size of the file.
  #
  def scan_files
    files = {}
    @glob.each do |glob|
      Dir.glob(glob).each do |fn|
        begin
          stat = File.stat fn
          next unless stat.file?
          files[fn] = stat
        rescue SystemCallError; end
      end
    end
    files
  end

  # call-seq:
  #    run
  #
  # Calling this method will enter the directory watcher's run loop. The
  # calling thread will not return until the +stop+ method is called.
  #
  # The run loop is responsible for scanning the directory for file changes,
  # and then dispatching events to registered listeners.
  #
  def run
    until @stop
      start = Time.now.to_f

      files = scan_files
      keys = [files.keys, @files.keys]  # current files, previous files

      find_added(files, *keys)
      find_modified(files, *keys)
      find_removed(*keys)

      notify_observers
      @files = files    # store the current file list for the next iteration

      nap_time = @interval - (Time.now.to_f - start)
      sleep nap_time if nap_time > 0
    end
  end

  # call-seq:
  #    find_added( files, cur, prev )
  #
  # Taking the list of current files, _cur_, and the list of files found
  # previously, _prev_, figure out which files have been added and generate
  # a new file added event for each.
  #
  def find_added( files, cur, prev )
    added = cur - prev
    added.each do |fn|
      files[fn].stable = @stable
      @events << Event.new(:added, fn)
    end
    self
  end

  # call-seq:
  #    find_removed( cur, prev )
  #
  # Taking the list of current files, _cur_, and the list of files found
  # previously, _prev_, figure out which files have been removed and
  # generate a new file removed event for each.
  #
  def find_removed( cur, prev )
    removed = prev - cur
    removed.each {|fn| @events << Event.new(:removed, fn)}
    self
  end

  # call-seq:
  #    find_modified( files, cur, prev )
  #
  # Taking the list of current files, _cur_, and the list of files found
  # previously, _prev_, find those that are common between them and determine
  # if any have been modified. Generate a new file modified event for each
  # modified file. Also, by looking at the stable count in the _files_ hash,
  # figure out if any files have become stable since being added or modified.
  # Generate a new stable event for each stabilized file.
  #
  def find_modified( files, cur, prev )
    (cur & prev).each do |key|
      cur_stat, prev_stat = files[key], @files[key]

      # if the modification time or the file size differs from the last
      # time it was seen, then create a :modified event
      if (cur_stat <=> prev_stat) != 0 or cur_stat.size != prev_stat.size
        @events << Event.new(:modified, key)
        cur_stat.stable = @stable

      # otherwise, if the count is not nil see if we need to create a
      # :stable event
      elsif !prev_stat.stable.nil?
        cur_stat.stable = prev_stat.stable - 1
        if cur_stat.stable == 0
          @events << Event.new(:stable, key)
          cur_stat.stable = nil
        end
      end
    end
    self
  end

  # call-seq:
  #    notify_observers
  #
  # If there are queued files events, then invoke the update method of each
  # registered observer in turn passing the list of file events to each.
  # The file events array is cleared at the end of this method call.
  #
  def notify_observers
    unless @events.empty?
      @observer_peers.each do |observer, func|
        begin; observer.send(func, *@events); rescue Exception; end
      end
      @events.clear
    end
  end

end  # class DirectoryWatcher

# :stopdoc:
# We need to add a 'stable' attribute to the File::Stat object
class File::Stat
  attr_accessor :stable
end
# :startdoc:

# EOF
