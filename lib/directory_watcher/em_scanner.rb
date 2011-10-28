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
# notifications instead of a periodic polling and stat of every file in the
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
class DirectoryWatcher::EmScanner < DirectoryWatcher::EventableScanner
  # call-seq:
  #    EmScanner.new( configuration )
  #
  def initialize( config )
    super(config)
  end

  # Called by EventablScanner#start to start the loop up and attach the periodic
  # timer that will poll the globs for new files.
  #
  def start_loop_with_attached_scan_timer
    return if @loop_thread
    unless EventMachine.reactor_running?
      @loop_thread = Thread.new {EventMachine.run}
      Thread.pass until EventMachine.reactor_running?
    end

    @timer = ScanTimer.new(self)
  end

  # Called by EventableScanner#stop to stop the loop as part of the shutdown
  # process.
  #
  def stop_loop
    if @loop_thread then
      EventMachine.next_tick do
        EventMachine.stop_event_loop
      end
      @loop_thread.kill
      @loop_thread = nil
    end
  end

  # :stopdoc:
  #
  # This is our tailored implementation of the EventMachine FileWatch class.
  # It receives notifications of file events and provides a mechanism to
  # translate the EventMachine events into objects to send to the Scanner that
  # it is initialized with.
  #
  # The Watcher only responds to modified and deleted events.
  #
  # This class is required by EventableScanner to institute file watching.
  #
  class Watcher < EventMachine::FileWatch
    def self.watch( path, scanner )
      EventMachine.watch_file path, Watcher, scanner
    end

    # Initialize the Watcher using with the given scanner
    # Post initialization, EventMachine will set @path
    #
    def initialize( scanner )
      @scanner = scanner
    end

    # EventMachine callback for when a watched file is deleted. We convert this
    # to a FileStat object for a removed file.
    #
    def file_deleted
      @scanner.on_removed(self, ::DirectoryWatcher::FileStat.for_removed_path(@path))
    end
    # Event Machine also sends events on file_moved which we'll just consider a
    # file deleted and the file added event will be picked up by the next scan
    alias :file_moved :file_deleted

    # EventMachine callback for when a watched file is modified. We convert this
    # to a FileStat object and send it to the collector
    def file_modified
      stat = File.stat @path
      @scanner.on_modified(self, ::DirectoryWatcher::FileStat.new(@path, stat.mtime, stat.size))
    end

    # Detach the watcher from the event loop.
    #
    # Required by EventableScanner as part of the shutdown process.
    #
    def detach
      EventMachine.next_tick do
        stop_watching
      end
    end
  end

  # Periodically execute a Scan.
  #
  # This object is used by EventableScanner to during shutdown.
  #
  class ScanTimer
    def initialize( scanner )
      @scanner = scanner
      @timer = EventMachine::PeriodicTimer.new( @scanner.interval, method(:on_scan) )
    end

    def on_scan
      @scanner.on_scan
    end

    # Detach the watcher from the event loop.
    #
    # Required by EventableScanner as part of the shutdown process.
    #
    def detach
      EventMachine.next_tick do
        @timer.cancel
      end
    end
  end
  # :startdoc:
end  # class DirectoryWatcher::EmScanner
end  # if HAVE_EM

# EOF
