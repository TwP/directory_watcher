# An Eventable Scanner is one that can be utilized by something that has an
# Event Loop. It is intended to be subclassed by classes that implement the
# specific event loop semantics for say EventMachine or Cool.io.
#
# The Events that the EventableScanner is programmed for are:
#
# on_scan     - this should be called every +interval+ times
# on_modified - If the event loop can monitor individual files then this should
#               be called when the file is modified
# on_removed  - Similar to on_modified but called when a file is removed.
#
# Sub classes are required to implement the following:
#
#   start_loop_with_attached_scan_timer() - Instance Method
#     This method is to start up the loop, if necessary assign to @loop_thread
#     instance variable the Thread that is controlling the event loop.
#
#     This method must also assign an object to @timer which is what does the
#     periodic scanning of the globs. This object must respond to +detach()+ so
#     that it may be detached from the event loop.
#
#   stop_loop() - Instance Method
#     This method must shut down the event loop, or detach these classes from
#     the event loop if we just attached to an existing event loop.
#
#   Watcher - An Embedded class
#     This is a class that must have a class method +watcher(path,scanner)+
#     which is used to instantiate a file watcher. The Watcher instance must
#     respond to +detach()+ so that it may be independently detached from the
#     event loop.
#
class DirectoryWatcher::EventableScanner
  include DirectoryWatcher::Logable

  # A Hash of Watcher objects.
  attr_reader :watchers

  # call-seq:
  #    EventableScanner.new( config )
  #
  # config - the Configuration instances
  #
  def initialize( config )
    @config = config
    @scan_and_queue = DirectoryWatcher::ScanAndQueue.new(config.glob, config.collection_queue)
    @watchers = {}
    @stopping = false
    @timer = nil
    @loop_thread = nil
    @paused = false
  end

  # The queue on which to put FileStat and Scan items.
  #
  def collection_queue
    @config.collection_queue
  end

  # The interval at which to scan
  #
  def interval
    @config.interval
  end

  # Returns +true+ if the scanner is currently running. Returns +false+ if
  # this is not the case.
  #
  def running?
    return !@stopping if @timer
    return false
  end

  # Start up the scanner. If the scanner is already running, nothing happens.
  #
  def start
    return if running?
    logger.debug "starting scanner"
    start_loop_with_attached_scan_timer
  end

  # Stop the scanner. If the scanner is not running, nothing happens.
  #
  def stop
    return unless running?
    logger.debug "stoping scanner"
    @stopping = true
    teardown_timer_and_watches
    @stopping = false
    stop_loop
  end

  # Pause the scanner.
  #
  # Pausing the scanner does not stop the scanning per se, it stops items from
  # being sent to the collection queue
  #
  def pause
    logger.debug "pausing scanner"
    @paused = true
  end

  # Resume the scanner.
  #
  # This removes the blockage on sending items to the collection queue.
  #
  def resume
    logger.debug "resuming scanner"
    @paused = false
  end

  # Is the Scanner currently paused.
  #
  def paused?
    @paused
  end

  # EventableScanners do not join
  #
  def join( limit = nil )
  end

  # Do a single scan and send those items to the collection queue.
  #
  def run
    logger.debug "running scan and queue"
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

  # This callback is invoked by the Timer instance when it is triggered by
  # the Loop. This method will check for added files and stable files
  # and notify the directory watcher accordingly.
  #
  def on_scan
    logger.debug "on_scan called"
    scan_and_watch_files
    progress_towards_maximum_iterations
  end

  # This callback is invoked by the Watcher instance when it is triggered by the
  # loop for file modifications.
  #
  def on_modified(watcher, new_stat)
    logger.debug "on_modified called"
    queue_item(new_stat)
  end

  # This callback is invoked by the Watcher instance when it is triggered by the
  # loop for file removals
  #
  def on_removed(watcher, new_stat)
    logger.debug "on_removed called"
    unwatch_file(watcher.path)
    queue_item(new_stat)
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
      logger.debug "enqueuing #{item} to #{collection_queue}"
      collection_queue.enq item
    end
  end


  # Run a single scan and turn on watches for all the files found in that scan
  # that do not already have watchers on them.
  #
  def scan_and_watch_files
    logger.debug "scanning and watching files"
    scan = @scan_and_queue.scan_and_queue
    scan.results.each do |stat|
      watch_file(stat.path)
    end
  end

  # Remove the timer and the watches from the event loop
  #
  def teardown_timer_and_watches
    @timer.detach rescue nil
    @timer = nil

    @watchers.each_value {|w| w.detach}
    @watchers.clear
  end

  # Create and return a new Watcher instance for the given filename _fn_.
  # A watcher will only be created once for a particular fn.
  #
  def watch_file( fn )
    unless @watchers[fn] then
      logger.debug "Watching file #{fn}"
      w = self.class::Watcher.watch(fn, self)
      @watchers[fn] = w
    end
  end

  # Remove the watcher instance from our tracking
  #
  def unwatch_file( fn )
    logger.debug "Unwatching file #{fn}"
    @watchers.delete(fn)
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
  # :startdoc:
end  # class DirectoryWatcher::Eventablecanner
