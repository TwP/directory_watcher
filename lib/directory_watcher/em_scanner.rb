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
class DirectoryWatcher::EmScanner

  # call-seq:
  #    EmScanner.new( options = {} )
  #
  # Create an EventMachine based scanner that will generate file events and
  # pass those events to the given Queue. See DirectoryWatcher::Scanner for
  # option definitions
  #
  def initialize( glob, interval, collection_queue )
    @scan_and_queue = DirectoryWatcher::ScanAndQueue.new(glob, collection_queue)
    @collection_queue = collection_queue

    @interval = interval

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

    EventMachine.next_tick( lambda { start_periodic_scan } )
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
      EventMachine.next_tick do
        EventMachine.stop_event_loop
      end
    end
  end

  # Pauses sending of FileStat and Scans items to the collection Queue.
  # The reactions of Watchers to existing will be ignored.
  #
  def pause
    @paused = true
  end

  # Resume sending of FileStat and Scan items to the collection Queue
  #
  def resume
    @paused = false
  end

  # Is the Scanner currently paused?
  #
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

  # Run a scan all by its lonesom
  #
  def run
    @scan_and_queue.scan_and_queue
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

  # Have we completed up to the maximum_iterations?
  #
  def finished_iterations?
    self.iterations >= self.maximum_iterations
  end

  # A Watcher told us that a file has been deleted. Remove the watcher from the
  # list of known watchers, and send a :removed event to the collection queue.
  #
  def on_removed( stat )
    unwatch_file(stat.path)
    logger.debug "on_removed #{stat.path}"
    queue_item(stat)
  end

  # A Watcher told us that a file has changed. So send the new Stat of that file
  # down collection_queue.
  #
  def on_modified( stat )
    logger.debug "on_modified #{stat.path}"
    queue_item(stat)
  end


  #######
  private
  #######

  # Send the given item to the collection queue
  #
  def queue_item( item )
    if paused? then
      logger.debug "Not queueing item, we're paused"
    else
      @collection_queue.enq item
    end
  end

  # Notify added and stable events on a periodic basis. The removed and modified
  # events will be issued via FileWatch objects. This timer isn't a periodic
  # timer since this 'possibly' could be an expensive operation, it is a on shot
  # timer that adds itself back to the event loop
  def start_periodic_scan
    unless @timer then
      @timer = EventMachine::PeriodicTimer.new( @interval ) do
        logger.debug "PeriodicTimer at #{@interval}"
        scan_and_watch_files
        progress_towards_maximum_iterations
      end
    end
  end

  def scan_and_watch_files
    scan = @scan_and_queue.scan_and_queue
    scan.results.each do |stat|
      watch_file(stat.path)
    end
  end

  # Create and return a new Watcher instance for the given filename _fn_.
  #
  def watch_file( fn )
    if (not @watchers[fn]) and File.exist?(fn) then
      logger.debug "Watching file #{fn}"
      @watchers[fn] = EventMachine.watch_file fn, Watcher, self
    end
  end

  def unwatch_file( fn )
    logger.debug "Unwatching file #{fn}"
    watcher = @watchers.delete(fn)
    # EM takes care of stopping the watch since the file is deleted
  end


  # Remove all timers and watchers from the event loop, we need to do this in
  # the event loop it self, as they could be executing currently.
  #
  def teardown_timer_and_watches
    EventMachine.next_tick do
      @timer.cancel rescue nil
      @timer = nil
    end

    EventMachine.next_tick do
      @watchers.each_value {|w| w.stop_watching }
      @watchers.clear
    end
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

  # :stopdoc:
  #
  # This is our tailored implementation of the EventMachine FileWatch class.
  # It receives notifications of file events and provides a mechanism to
  # translate the EventMachine events into objects to send to the Scanner that
  # it is initialized with.
  #
  # The Watcher only reponds to modified and deleted events.
  #
  # EM will set the '@path' instance variable after initialization.
  #
  class Watcher < EventMachine::FileWatch
    def initialize( scanner )
      @scanner = scanner
      logger.debug "Watcher initialized with Scanner #{@scanner}"
    end

    def stat
      if test ?e, @path then
        stat = File.stat @path
        return ::DirectoryWatcher::FileStat.new(@path, stat.mtime, stat.size)
      else
        return ::DirectoryWatcher::FileStat.for_removed_path(@path)
      end
    end

    def file_deleted
      @scanner.on_removed(stat)
    end
    alias :file_moved :file_deleted

    def file_modified
      @scanner.on_modified(stat)
    end
  end
  # :startdoc:

end  # class DirectoryWatcher::EmScanner
end  # if HAVE_EM

# EOF
