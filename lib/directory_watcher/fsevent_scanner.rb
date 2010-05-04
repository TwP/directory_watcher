
begin
  require 'fsevent'
  DirectoryWatcher::HAVE_FSEVENT = true
rescue LoadError
  DirectoryWatcher::HAVE_FSEVENT = false
end

if DirectoryWatcher::HAVE_FSEVENT

# The FSEvent scanner is only availabe on Max OS X systems running version
# 10.5 or greater of the OS (Leopard and Snow Leopard). You must install the
# ruby-fsevent gem to use the FSEvent scanner.
#
class DirectoryWatcher::FseventScanner < DirectoryWatcher::Scanner

  # call-seq:
  #    FseventScanner.new( directory ) { |events| block }
  #
  # Create an FSEvent based scanner that will generate file events and pass
  # those events (as an array) to the given _block_.
  #
  def initialize( dir, &block )
    super(dir, &block)
    @notifier = FSEvent.new(File.expand_path(dir), 0.1)
  end

  # Start the scanner thread. If the scanner is already running, this method
  # will return without taking any action.
  #
  def start
    return if running?

    @stop = false
    run_once
    @notifier.start
    @thread = Thread.new(self) {|scanner| scanner.__send__ :run_loop}
    self
  end

  # Stop the scanner thread. If the scanner is already stopped, this method
  # will return without taking any action.
  #
  def stop
    return unless running?

    @stop = true
    @notifier.stop
    @thread.wakeup if @thread.status == 'sleep'
    @thread.join
    self
  ensure
    @thread = nil
  end

  #
  #
  def glob=( value )
    @glob_hash = (@glob_hash || Hash.new).clear
    @glob = value.map {|g| File.expand_path(g)}

    @glob.each do |g|
      dir = File.dirname(g)
      dir.gsub!(%r/\*{1,2}/) {|m| m.length == 2 ? '.*?' : '[^\/]+'}
      dir << '/?'
      @glob_hash[Regexp.new(dir)] = File.basename(g)
    end
  end


private

  # Using the configured glob pattern, scan the directory for all files and
  # return a hash with the filenames as keys and +FileStat+ objects as the
  # values. The +FileStat+ objects contain the mtime and size of the file.
  #
  def scan_files( directories = nil )
    return super() if directories.nil?
    files = {}
    ary = []

    directories.each do |dir|
      @glob_hash.each do |rgxp,glob|
        next unless rgxp =~ dir
        ary.concat Dir.glob(File.join(dir, glob))
      end
    end

    ary.each do |fn|
      next if files.key? fn
      begin
        stat = File.stat fn
        next unless stat.file?
        files[fn] = ::DirectoryWatcher::FileStat.new(stat.mtime, stat.size)
      rescue SystemCallError; end
    end

    files
  end

  # Calling this method will enter the scanner's run loop. The
  # calling thread will not return until the +stop+ method is called.
  #
  # The run loop is responsible for scanning the directory for file changes,
  # and then dispatching events to registered listeners.
  #
  def run_loop
    start = Time.now.to_f
    timeout = lambda { @interval - (Time.now.to_f - start)}

    until @stop
      # receive notifications about changed directories
      directories = @notifier.changes(timeout[])
      next if @stop

      # process the changed directories
      unless directories.nil?
        directories.uniq!
        files = scan_files(directories)
        cur, prev = [files.keys, @files.keys]  # current files, previous files

        find_added(files, cur, prev)
        _find_modified(files, cur, prev)

        directories.each {|dir| cur.delete_if {|fn| fn.index(dir) != 0}}
        removed = find_removed(cur, prev)

        @files.merge! files    # store the current file list for the next iteration
        removed.each {|fn| @files.delete fn}
      end

      # if our timeout has expired, then reset the timeout and look for stable files
      if timeout[] <= 0
        start = Time.now.to_f
        _find_stable
      end

      notify
    end
  end

  # call-seq:
  #    _find_modified( files, cur, prev )
  #
  # Taking the list of current files, _cur_, and the list of files found
  # previously, _prev_, find those that are common between them and determine
  # if any have been modified. Generate a new file modified event for each
  # modified file.
  #
  def _find_modified( files, cur, prev )
    (cur & prev).each do |key|
      cur_stat, prev_stat = files[key], @files[key]

      # if the modification time or the file size differs from the last
      # time it was seen, then create a :modified event
      if cur_stat != prev_stat
        @events << ::DirectoryWatcher::Event.new(:modified, key)
        cur_stat.stable = @stable
      else
        cur_stat.stable = prev_stat.stable
      end
    end
    nil
  end

  # call-seq:
  #    find_stable
  #
  # Look for any files that have a stable count and decrement the count by
  # one. If the count goes to zero, then generate a stable event for the file.
  #
  def _find_stable
    @files.each do |key, stat|
      next if stat.stable.nil?
      stat.stable -= 1

      if stat.stable <= 0
        @events << ::DirectoryWatcher::Event.new(:stable, key)
        stat.stable = nil
      end
    end
    nil
  end

end  # class DirectoryWatcher::FseventScanner
end  # if HAVE_FSEVENT

