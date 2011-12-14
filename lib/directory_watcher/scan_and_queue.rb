# ScanAndQueue creates a Scan from its input globs and then sends that Scan to
# its Queue.
#
# Every time scan_and_queue is called a new scan is created an sent to the
# queue.
class DirectoryWatcher::ScanAndQueue
  def initialize(glob, ignore_glob, queue)
    @globs = glob
    @ignore_globs = ignore_glob
    @queue = queue
  end

  # Create and run a Scan and submit it to the Queue.
  #
  # Returns the Scan that was run
  def scan_and_queue
    scan = ::DirectoryWatcher::Scan.new(@globs, @ignore_globs)
    scan.run
    logger.debug "Scanned #{@globs} and found #{scan.run.size} items"
    scan.results.each { |s| logger.debug "#{s}" }
    @queue.enq scan
    return scan
  end
end
