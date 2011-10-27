begin
  require 'eventmachine'
  DirectoryWatcher::HAVE_EM = true
rescue LoadError
  DirectoryWatcher::HAVE_EM = false
end

if DirectoryWatcher::HAVE_EM

# Set up the appropriate polling options
[:epoll, :kqueue].each do |poll|
  if EventMachine.send("#{poll}?") then
    EventMachine.send("#{poll}=", true )
    break
  end
end

# The EmScanner uses the EventMachine reactor loop to monitor changes to
# files in the watched directory. This scanner is more efficient than the
# pure Ruby scanner because it relies on the operating system kernel
# notifictions instead of a periodic polling and stat of every file in the
# watched directory (the technique used by the Scanner class).
#
# EventMachine cannot notify us when a file is added to the watched
# directory; therefore, added files are only picked up when we apply the
# glob pattern to the directory. This is done at the configured interval.
#
# Notes:
#
#  * Kqueue does not generate notifications when "touch" is used to update
#    a file's timestamp. This applies to Mac and BSD systems.
#
#  * New files are detected only when the watched directory is polled at the
#    configured interval.
#
class DirectoryWatcher::EmScanner < ::DirectoryWatcher::Scanner

  # call-seq:
  #    EmScanner.new( options = {} )
  #
  # Create an EventMachine based scanner that will generate file events and
  # pass those events to the given Queue. See DirectoryWatcher::Scanner for
  # option definitions
  #
  def initialize( options = {} )
    super(options)
    @watchers = {}
    @timer = nil
    @stopping = false         # A guard while we are shutting down
    @paused = false
    @em_thread = nil          # The reactor thread, if we start it up.
    @maximum_iterations = nil # set if we actually have maximum iterations
    @iterations = 0           # count iterations, only if maximum iterations
  end

  # Returns +true+ if the scanner is currently running. Returns +false+ if
  # this is not the case.
  #
  def running?
    return !@stopping if @timer
    return false
  end

  # Before we start properly, we need to reset everything and start watching the
  # exising files
  #
  def before_starting
    super
    setup_existing_watches_and_alert_removed
  end

  # Start the EventMachine scanner. If the scanner has already been started
  # this method will return without taking any action.
  #
  # If the EventMachine reactor is not running, it will be started by this
  # method.
  #
  # Once we have a reactor, run the before starting action, and when that is
  # done, kick off the periodic timer.
  #
  def start
    return if running?

    unless EventMachine.reactor_running?
      @em_thread = Thread.new {EventMachine.run}
      Thread.pass until EventMachine.reactor_running?
    end

    EventMachine.defer( lambda { before_starting },
                        lambda { start_periodic_timer } )
  end

  # Stop the EventMachine scanner. If the scanner is already stopped this
  # method will return without taking any action.
  #
  # The EventMachine reactor will _not_ be stopped by this method. It is up
  # to the user to stop the reactor using the EventMachine#stop_event_loop
  # method.
  #
  def stop
    return unless running?
    @stopping = true
    teardown_timer_and_watches
    @stopping = false
    if @em_thread then
      EventMachine.stop_event_loop
    end
  end

  # Pauses the emitting of events. While the scanner is paused, no events will
  # be emitted. If existing files that have watchers on on them are modified,
  # then those events will be lost.
  #
  def pause
    @paused = true
  end

  # Resume emitting events
  #
  def resume
    @paused = false
  end

  def paused?
    @paused
  end

  # call-seq:
  #    join( limit = nil )
  #
  # This is a no-op method for the EventMachine file scanner.
  #
  def join( limit = nil )
  end

  # Create and return a new Watcher instance for the given filename _fn_.
  #
  def watch_file( fn )
    @watchers[fn] = EventMachine.watch_file fn, Watcher, self
  end

  # Delete the given file from the system and fire the appripriate event
  #
  def delete_file( fn )
    return if paused?
    watcher = @watchers.delete(fn)
    @files.delete(fn)
    notify(::DirectoryWatcher::Event.new(:removed, fn))
  end

  # Modify the given file in the system and fire the appripriate event
  #
  def modify_file( fn )
    return if paused?
    @files[fn] = @watchers[fn].stat
    notify(::DirectoryWatcher::Event.new(:modified, fn))
  end

  # Setting maximum iterations means hooking into the periodic timer event and
  # counting the number of times it is going on. This also resets the current
  # iterations count
  #
  def maximum_iterations=(value)
    unless value.nil?
      value = Integer(value)
      raise ArgumentError, "maximum iterations must be >= 1" unless value >= 1
    end
    @iterations = 0
    @maximum_iterations = value
  end
  attr_reader :maximum_iterations
  attr_reader :iterations

  # Notify added and stable events on a periodic basis. The removed and modified
  # events will be issued via FileWatch objects. This timer isn't a periodic
  # timer since this 'possibly' could be an expensive operation, it is a on shot
  # timer that adds itself back to the event loop
  def start_periodic_timer
    unless @timer then
      @timer = EventMachine::PeriodicTimer.new( interval ) do
        notify_added_and_stable
        progress_towards_maximum_iterations
      end
    end
  end

  #######
  private
  #######

  # Before the peridic timers are kicked off and we start using the event loop
  # proper, we need to setup file watches on all the existing files. This is
  # because pre_load may have happened and we need to watch those files. And
  # some of those files may have disappared from the time of the scan to the
  # time we are called
  #
  def setup_existing_watches_and_alert_removed
    events = []
    to_watch = []
    files.keys.each do |fn|
      if File.exist?( fn ) then
        to_watch << fn
      else
        files.delete fn
        events << ::DirectoryWatcher::Event.new(:removed, fn)
      end
    end
    # do this so that the notifications for removed files will probably go out
    # before anything that might happen to the watched files.
    notify(events) unless events.empty?

    to_watch.each { |fn| watch_file(fn) }
  end

  def teardown_timer_and_watches
    @timer.cancel rescue nil
    @timer = nil

    @watchers.each_value {|w| w.stop_watching }
    @watchers.clear
  end

  # EventMachine cannot notify us when new files are added to the watched
  # directory, or when nothing happens to a file. This method finds all
  # added and stable files and issues events for them.
  #
  # This method ONLY looks for new and stable items, even though it could find
  # the modified and removed, it leaves those for the Watchers.
  #
  # This method is run inside a periodic timer in EM.
  #
  def notify_added_and_stable
    return if paused?
    events = []
    scan_files.each do |fn, new_stat|
      if cached_stat = @files[fn] then
        if stable_event?( cached_stat, new_stat ) then
          events << ::DirectoryWatcher::Event.new(:stable, fn)
        elsif modified_event?( cached_stat, new_stat ) then
          events << ::DirectoryWatcher::Event.new(:modified, fn)
        end
      else
        @files[fn] = watch_file(fn).stat
        events << ::DirectoryWatcher::Event.new(:added, fn)
      end
    end
    notify(events)
  end

  # Make progress towards maximum iterations. And if we get there, then stop
  # monitoring files.
  #
  def progress_towards_maximum_iterations
    if maximum_iterations then
      @iterations += 1
      stop if finished_iterations?
    end
  end

  # have we finished the maximum number of iterations we should
  #
  def finished_iterations?
    self.iterations >= self.maximum_iterations
  end

  # Return whether or not the two stats are the same, and if they are the same
  # should a stable event be issued.
  #
  def stable_event?( cur_stat, new_stat )
    if cur_stat == new_stat and !cur_stat.stable.nil? then
      cur_stat.stable -= 1
      if cur_stat.stable <= 0 then
        cur_stat.stable = nil
        return true
      end
    end
    return false
  end

  # Return whether or not the two stats are different enough to emit a modified
  # event. In this case we are only checking the mtimes
  def modified_event?( cur_stat, new_stat )
    if cur_stat.mtime != new_stat.mtime then
      cur_stat.mtime = new_stat.mtime
      return true
    end
    return false
  end

  # :stopdoc:
  #
  # This is our tailored implementation of the EventMachine FileWatch class.
  # It receives notifications of file events and provides a mechanism to
  # translate the EventMachine events into DirectoryWatcher events.
  #
  # EM will set the '@path' instance variable after initialization.
  #
  class Watcher < EventMachine::FileWatch
    def initialize( scanner )
      @scanner = scanner
      @active = true
    end

    def stat
      return unless test ?e, @path
      stat = File.stat @path
      ::DirectoryWatcher::FileStat.new(stat.mtime, stat.size, @scanner.stable)
    end

    def file_deleted
      EventMachine.next_tick do
        @scanner.delete_file(path)
      end
    end
    alias :file_moved :file_deleted

    def file_modified
      EventMachine.next_tick do
        @scanner.modify_file(path)
      end
    end
  end
  # :startdoc:

end  # class DirectoryWatcher::EmScanner
end  # if HAVE_EM

# EOF
