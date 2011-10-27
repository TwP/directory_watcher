begin
  require 'coolio'
  DirectoryWatcher::HAVE_COOLIO = true
rescue LoadError
  DirectoryWatcher::HAVE_COOLIO = false
end

if DirectoryWatcher::HAVE_COOLIO

# The CoolioScanner uses the Coolio loop to monitor changes to files in the
# watched directory. This scanner is more efficient than the pure Ruby
# scanner because it relies on the operating system kernel notifictions
# instead of a periodic polling and stat of every file in the watched
# directory (the technique used by the Scanner class).
#
class DirectoryWatcher::CoolioScanner
  # call-seq:
  #    CoolioScanner.new( glob, interval, collection_queue )
  #
  def initialize( glob, interval, collection_queue )
    @scan_and_queue = DirectoryWatcher::ScanAndQueue.new(glob, collection_queue)
    @collection_queue = collection_queue
    @interval = interval

    @stopping = false
    @watchers = {}
    @timer = nil
    @cio_thread = nil
    @paused = false
  end
  attr_reader :interval

  def running?
    !@timer.nil?
  end

  # Start the Coolio scanner loop. If the scanner is already running, this method
  # will return without taking any action.
  #
  def start
    return if running?

    @timer = PeriodicTimer.new self
    @cio_thread = Thread.new {
      @timer.attach(coolio_loop)
      coolio_loop.run
    }
    logger.debug "Started loop in thread #{@cio_thread}"
  end


  # Stop the Cool.io scanner loop. If the Scanner is already stopped, this
  # methid will return without taking any action.
  def stop
    return unless running?
    @stopping = true
    teardown_timer_and_watches
    @stopping = false
    if @cio_thread then
      @cio_thread._coolio_loop.stop rescue nil 
      @cio_thread.kill
      @cio_thread = nil
    end
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

  # :stopdoc:
  #
  # This callback is invoked by a Watcher instance when some change has
  # occured on the file. The scanner determines if the file has been
  # modified or deleted and notifies the directory watcher accordingly.
  #
  def on_change(watcher, new_stat)
    queue_item(new_stat)
  end

  # This callback is invoked by the Timer instance when it is triggered by
  # the Coolio loop. This method will check for added files and stable files
  # and notify the directory watcher accordingly.
  #
  def on_scan
    scan_and_watch_files
    progress_towards_maximum_iterations
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
    w = Watcher.new(fn, self)
    w.attach(coolio_loop)
    @watchers[fn] = w
  end

  def unwatch_file( fn )
    logger.debug "Unwatching file #{fn}"
    watcher = @watchers.delete(fn)
    # EM takes care of stopping the watch since the file is deleted
  end

  def coolio_loop
    if @cio_thread then
      @cio_thread._coolio_loop
    else
      Thread.current._coolio_loop
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
  class Watcher < Coolio::StatWatcher
    def initialize( fn, scanner )
      # for file watching, we want to make sure this happens at a reasonable
      # value, so set it to 0 if the scanner.interval is > 5 seconds. This will
      # make it use the system value, and allow us to test.
      i = scanner.interval < 5 ? scanner.interval : 0
      super(fn, i)
      @scanner = scanner
    end

    def on_change( prev_stat, current_stat )
      new_stat = stat(current_stat)
      @scanner.on_change(self, new_stat)
    end

    def stat( system_stat )
      if File.exist?(path) then
        return ::DirectoryWatcher::FileStat.new(path, system_stat.mtime, system_stat.size)
      else
        return ::DirectoryWatcher::FileStat.for_removed_path(path)
      end
    end
  end

  class PeriodicTimer < Coolio::TimerWatcher
    def initialize( scanner )
      super(scanner.interval, true)
      @scanner = scanner
    end

    def on_timer( *args )
      @scanner.on_scan
    end
  end
  # :startdoc:
end  # class DirectoryWatcher::CoolioScanner

end  # if DirectoryWatcher::HAVE_COOLIO

# EOF
