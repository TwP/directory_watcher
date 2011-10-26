class DirectoryWatcher
  # A Scan is the scan of a full directory structure with the ability to iterate
  # over the results, or return them as a full dataset
  #
  #   Scan.new( globs ).each do |fn, stat|
  #     ...
  #   end
  #
  #   Scan.new( globs ) do |scan|
  #     hash = scan.results
  #   end
  #
  #   s = Scan.new( globs )
  #   s.scan
  #
  class Scan
    def initialize( globs )
      @globs = [ globs ].flatten
      @results = Hash.new
    end

    # Iterate over each item that matches the glob.
    # The item yeilded is a ::DirectoryWatcher::FileStat object.
    #
    def each( &block )
      @results.clear
      each_glob do |glob|
        glob.each do |fn|
          if stat = file_stat( fn ) then
            @results[fn] = stat
            yield stat if block_given?
          end
        end
      end
    end

    # Return the completed results

    #######
    private
    #######

    # Return the stat of of the file in question. If the item is not a file,
    # then return the value of the passed in +if_not_file+
    #
    def file_stat( fn, if_not_file = false )
      stat = File.stat fn
      return if_not_file unless stat.file?
      return DirectoryWatcher::FileStat.new( fn, stat.mtime, stat.size )
    rescue SystemCallError => e

      # swallow
      # logger.error "Error
    end

    # Iterate over each glob, yielding it
    #
    def each_glob( &block )
      @results.empty
      @globs.each do |glob|
        yield glob
      end
    end
  end
end
