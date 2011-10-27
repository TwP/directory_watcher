# FileStat contains stat information about a single file.
#
class DirectoryWatcher::FileStat

  # The fully expanded path of the file
  attr_reader :path

  # The last modified time of the file
  attr_accessor :mtime

  # The size of the file in bytes
  attr_accessor :size

  def self.for_removed_path( path )
    ::DirectoryWatcher::FileStat.new(path, nil, nil)
  end

  def initialize( path, mtime, size )
    @path = path
    @mtime = mtime
    @size = size
  end

  def removed?
    @mtime.nil? || @size.nil?
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
