# The Scanner is responsible for polling the watched directory at a regular
# interval and generating a Scan which it will then send down the collection
# queue to the Collector.
#
# The Scanner is a pure Ruby class, and as such it works across all Ruby
# interpreters on the major platforms. This also means that it can be
# processor intensive for large numbers of files or very fast update
# intervals. Your mileage will vary, but it is something to keep an eye on.
#
class DirectoryWatcher::Scanner
  include DirectoryWatcher::Threaded
  include DirectoryWatcher::Logable

  # call-seq:
  #    Scanner.new( configuration )
  #
  # From the Configuration instance passed in Scanner uses:
  #
  # glob             - Same as that in DirectoryWatcher
  # interval         - Same as that in DirectoryWatcher
  # collection_queue - The Queue to send the Scans too.
  #                    the other end of this queue is connected to a Collector
  #
  # The Scanner is not generally used out side of a DirectoryWatcher so this is
  # more of an internal API
  #
  #def initialize( glob, interval, collection_queue )
  def initialize( config )
    @config = config
    @scan_and_queue = ::DirectoryWatcher::ScanAndQueue.new( @config.glob, @config.collection_queue )
  end

  # Set the interval before starting the loop.
  # This allows for interval to be set AFTER the DirectoryWatcher instance is
  # allocated but before it is started.
  def before_starting
    self.interval = @config.interval
  end

  # Performs exactly one scan of the directory and sends the
  # results to the Collector
  #
  def run
    @scan_and_queue.scan_and_queue
  end
end
