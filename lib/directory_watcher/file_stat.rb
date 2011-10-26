class DirectoryWatcher
  # FileStat contains stat information about a single file.
  # 
  class FileStat

    # The fully expanded path of the file
    attr_reader :path

    # The last modified time of the file
    attr_accessor :mtime

    # The size of the file in bytes
    attr_accessor :size

    # The stable count, used to determine if hte file is 'stable' or not.
    attr_accessor :stable

    def initialize( path, mtime, size, stable = nil)
      @path = path
      @mtime = mtime
      @size = size
      @stable = stable
    end

    def eql?( other )
      return false unless other.instance_of? FileStat
      self.mtime == other.mtime and self.size == other.size
    end
    alias :== :eql?
  end
end
