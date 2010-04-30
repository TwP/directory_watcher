
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
  #    FseventScanner.new { |events| block }
  #
  # Create an FSEvent based scanner that will generate file events and pass
  # those events (as an array) to the given _block_.
  #
  def initialize( &block )
    super(&block)
    @notifier = Notifier.new
  end

  # Start the scanner thread. If the scanner is already running, this method
  # will return without taking any action.
  #
  def start
    return if running?

    @stop = false
    @thread = Thread.new(self) {|scanner| scanner.__send__ :run_loop}
    @notifier.start
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
    @dir_hash = (@dir_hash || Hash.new {|h,k| h[k] = Array.new}).clear
    @glob = value.map {|g| File.expand_path(g)}

    @glob.each do |g|
      dir = File.dirname(g) << File::SEPARATOR
      if dir =~ %r/\*\*/
        g = File.basename(g)
        Dir[dir].each {|d| @dir_hash[d] << File.join(d,g)}
      else
        @dir_hash[dir] << File.basename(g)
      end
    end

    @dir_hash.each_value {|ary| ary.uniq!}
    @notifier.watch_directories(@dir_hash.keys)
    @notifier.restart if running?
  end


private

  # Using the configured glob pattern, scan the directory for all files and
  # return a hash with the filenames as keys and +FileStat+ objects as the
  # values. The +FileStat+ objects contain the mtime and size of the file.
  #
  def scan_files( directories = nil )
    files = {}
    ary = []
    directories ||= @dir_hash.keys

    directories.each do |dir|
      next unless @dir_hash.key? dir
      @dir_hash[dir].each {|glob| ary.concat(Dir.glob(glob))}
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
      directories = @notifier.changed_directories(timeout[])
      next if @stop
$stdout.puts directories.inspect
$stdout.puts timeout[].inspect
      # process the changed directories
      unless directories.nil?
        files = scan_files(directories)
$stdout.puts files.keys.sort.inspect
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

  # :stopdoc:
  class Notifier < FSEvent
    SIZEOF_INT = [42].pack('I').size

    def initialize
      super

      @rd, @wr = IO.pipe
      @rd_select = [@rd]
    end

    alias :_start :start
    def start
      Thread.new(self) {|notifier| notifier._start}
    end

    def restart
      self.stop
      self.start
    end

    def on_change( directories )
      data = Marshal.dump directories
      @wr.write [data.size].pack('I')
      @wr.write data
    end

    def changed_directories( timeout = nil )
      r, w, e = Kernel.select(@rd_select, nil, nil, timeout) rescue nil
      return if r.nil?

      data = @rd.read SIZEOF_INT
      return if data.nil?

      size = data.unpack('I').first
      data = @rd.read size
      return if data.nil?

      Marshal.load(data) rescue data
    end

    alias :changes :changed_directories
    alias :watch :watch_directories
  end
  # :startdoc:

end  # class DirectoryWatcher::FseventScanner
end  # if HAVE_FSEVENT

