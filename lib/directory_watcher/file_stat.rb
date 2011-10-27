# FileStat contains stat information about a single file.
#
class DirectoryWatcher::FileStat

  # The fully expanded path of the file
  attr_reader :path

  # The last modified time of the file
  attr_accessor :mtime

  # The size of the file in bytes
  attr_accessor :size

  def initialize( path, mtime, size )
    @path = path
    @mtime = mtime
    @size = size
  end

  def eql?( other )
    return false unless other.instance_of? self.class
    self.mtime == other.mtime and self.size == other.size
  end
  alias :== :eql?

  def to_s
    "<#{self.class.name} path: #{path} mtime: #{mtime} size: #{size}>"
  end
end
