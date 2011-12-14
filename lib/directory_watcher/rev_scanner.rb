begin
  require 'rev'
  DirectoryWatcher::HAVE_REV = true
rescue LoadError
  DirectoryWatcher::HAVE_REV = false
end

if DirectoryWatcher::HAVE_REV

# Deprecated:
#
# The RevScanner uses the Rev loop to monitor changes to files in the
# watched directory. This scanner is more efficient than the pure Ruby
# scanner because it relies on the operating system kernel notifications
# instead of a periodic polling and stat of every file in the watched
# directory (the technique used by the Scanner class).
#
# The RevScanner is essentially the exact same as the CoolioScanner with class
# names changed and using _rev_loop instead of _coolio_loop. Unfortunately the
# RevScanner cannot be a sub class of CoolioScanner because of C-extension
# reasons between the rev and coolio gems
#
# Rev cannot notify us when a file is added to the watched
# directory; therefore, added files are only picked up when we apply the
# glob pattern to the directory. This is done at the configured interval.
#
class DirectoryWatcher::RevScanner < ::DirectoryWatcher::EventableScanner
  # call-seq:
  #    RevScanner.new( glob, interval, collection_queue )
  #
  def initialize( glob, interval, collection_queue )
    super(glob, interval, collection_queue)
  end

  # Called by EventablScanner#start to start the loop up and attach the periodic
  # timer that will poll the globs for new files.
  #
  def start_loop_with_attached_scan_timer
    return if @loop_thread
    @timer = ScanTimer.new( self )
    @loop_thread = Thread.new {
      @timer.attach(event_loop)
      event_loop.run
    }
  end

  # Called by EventableScanner#stop to stop the loop as part of the shutdown
  # process.
  #
  def stop_loop
    if @loop_thread then
      event_loop.stop rescue nil
      @loop_thread.kill
      @loop_thread = nil
    end
  end

  # Return the rev loop object
  #
  # This is used during the startup, shutdown process and for the Watcher to
  # attach and detach from the event loop
  #
  def event_loop
    if @loop_thread then
      @loop_thread._rev_loop
    else
      Thread.current._rev_loop
    end
  end

  # :stopdoc:
  #
  # Watch files using the Rev::StatWatcher.
  #
  # The rev +on_change+ callback is converted to the appropriate +on_removed+
  # and +on_modified+ callbacks for the EventableScanner.
  class Watcher < ::Rev::StatWatcher
    def self.watch(fn, scanner )
      new(fn, scanner)
    end

    def initialize( fn, scanner )
      # for file watching, we want to make sure this happens at a reasonable
      # value, so set it to 0 if the scanner.interval is > 5 seconds. This will
      # make it use the system value, and allow us to test.
      i = scanner.interval < 5 ? scanner.interval : 0
      super(fn, i)
      @scanner = scanner
      attach(scanner.event_loop)
    end

    # Rev uses on_change so we convert that to the appropriate
    # EventableScanner calls. Unlike Coolio, Rev's on_change() takes no
    # parameters
    #
    def on_change
      if File.exist?(path) then
        @scanner.on_removed(self, ::DirectoryWatcher::FileStat.for_removed_path(path))
      else
        stat = File.stat(path)
        @scanner.on_modified(self, ::DirectoryWatcher::FileStat.new(path, stat.mtime, stat.size))
      end
    end
  end

  # Periodically execute a Scan. Hook this into the EventableScanner#on_scan
  #
  class ScanTimer< Rev::TimerWatcher
    def initialize( scanner )
      super(scanner.interval, true)
      @scanner = scanner
    end

    def on_timer( *args )
      @scanner.on_scan
    end
  end

end  # class DirectoryWatcher::RevScanner

end  # if DirectoryWatcher::HAVE_REV
