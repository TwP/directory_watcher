# An Eventable Scanner is one that can be utilized by something that has an
# Event Loop.
# 
# The Events that the EventableScanner is programmed for are:
#
# on_scan     - this should be called every +interval+ times
# on_modified - If the event loop can monitor individual files then this should
#               be called when the file is modified
# on_removed  - Similar to on_modified but called when a file is removed.
#
class DirectoryWatcher::EventableScanner
  # This is how often +on_scan+ should be called
  attr_reader :interval

  # A Hash of Watcher objects.
  attr_reader :watchers

  # call-seq:
  #    EventableScanner.new( glob, interval, collection_queue )
  #
  def initialize( glob, interval, collection_queue )
    @scan_and_queue = DirectoryWatcher::ScanAndQueue.new(glob, collection_queue)
    @collection_queue = collection_queue
    @interval = interval
    @watchers = {}
    @stopping = false
    @timer = nil
    @loop_thread = nil
    @paused = false
  end

  # Returns +true+ if the scanner is currently running. Returns +false+ if
  # this is not the case.
  #
  def running?
    return !@stopping if @timer
    return false
  end

  def start
    return if running?
    logger.debug "starting"
    start_loop_with_attached_scan_timer
  end

  def stop
    return unless running?
    logger.debug "stopting"
    @stopping = true
    teardown_timer_and_watches
    @stopping = false
    stop_loop
  end

  def pause
    logger.debug "pausing"
    @paused = true
  end

  def resume
    logger.debug "resuming"
    @paused = false
  end

  def paused?
    @paused
  end

  # Eventable Scanners do not join
  def join( limit = nil )
  end

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

  # This callback is invoked by the Timer instance when it is triggered by
  # the Loop. This method will check for added files and stable files
  # and notify the directory watcher accordingly.
  #
  def on_scan
    scan_and_watch_files
    progress_towards_maximum_iterations
  end

  # This callback is invoked by the Watcher instance when it is triggered by teh
  # loop for file modifications.
  #
  def on_modified(watcher, new_stat)
    queue_item(new_stat)
  end

  # This callback is invoked by the Watcher instance when it is triggered by the
  # loop for file removals
  #
  def on_removed(watcher, new_stat)
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
      @collection_queue.enq item
    end
  end


  def scan_and_watch_files
    scan = @scan_and_queue.scan_and_queue
    scan.results.each do |stat|
      watch_file(stat.path)
    end
  end

  # remove the timer and the watches from the event loop
  def teardown_timer_and_watches
    @timer.detach rescue nil
    @timer = nil

    @watchers.each_value {|w| w.detach}
    @watchers.clear
  end


  # Create and return a new Watcher instance for the given filename _fn_.
  #
  def watch_file( fn )
    logger.debug "Watching file #{fn}"
    w = self.class::Watcher.watch(fn, self)
    @watchers[fn] = w
  end

  # Remove the watcher instance from our tracking
  #
  def unwatch_file( fn )
    logger.debug "Unwatching file #{fn}"
    watcher = @watchers.delete(fn)
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
