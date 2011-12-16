# ScanAndQueue creates a Scan from its input globs and then sends that Scan to
# its Queue.
#
# Every time scan_and_queue is called a new scan is created an sent to the
# queue.
class DirectoryWatcher::ScanAndQueue

  def initialize( glob, queue )
    @globs = glob
    @queue =queue
  end

  # Create and run a Scan and submit it to the Queue.
  #
  # Returns the Scan that was run
  def scan_and_queue
    scan = ::DirectoryWatcher::Scan.new( @globs )
    scan.run
    @queue.enq scan
    return scan
  end
end
