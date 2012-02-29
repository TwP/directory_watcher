# A Scan is the scan of a full directory structure with the ability to iterate
# over the results, or return them as a full dataset
#
#   results = Scan.new( globs ).run
#
class DirectoryWatcher::Scan

  def initialize( globs = Array.new )
    @globs = [ globs ].flatten
    @results = Array.new
  end

  # Run the entire scan and collect all the results. The Scan will only ever
  # be run once.
  #
  # Return the array of FileStat results
  def run
    results
  end

  # Return the results of the scan. If the scan has not been run yet, then run
  # it
  def results
    @results = collect_all_stats if @results.empty?
    return @results
  end

  #######
  private
  #######

  # Collect all the Stats into an Array and return them
  #
  def collect_all_stats
    r = []
    each { |stat| r << stat }
    return r
  end

  # Iterate over each glob, yielding it
  #
  def each_glob( &block )
    @globs.each do |glob|
      yield glob
    end
  end

  # Iterate over each item that matches the glob.
  # The item yielded is a ::DirectoryWatcher::FileStat object.
  #
  def each( &block )
    each_glob do |glob|
      Dir.glob(glob).each do |fn|
        if stat = file_stat( fn ) then
          yield stat if block_given?
        end
      end
    end
  end

  # Return the stat of of the file in question. If the item is not a file,
  # then return the value of the passed in +if_not_file+
  #
  def file_stat( fn, if_not_file = false )
    stat = File.stat fn
    return if_not_file unless stat.file?
    return DirectoryWatcher::FileStat.new( fn, stat.mtime, stat.size )
  rescue SystemCallError => e
    # swallow
    $stderr.puts "Error Stating #{fn} : #{e}"
  end
end
