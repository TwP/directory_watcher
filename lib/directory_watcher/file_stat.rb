# FileStat contains file system information about a single file including:
#
# path  - The fully expanded path of the file
# mtime - The last modified time of the file, as a Time object
# size  - The size of the file, in bytes.
#
# The FileStat object can also say if the file is removed of not.
#
class DirectoryWatcher::FileStat

  # The fully expanded path of the file
  attr_reader :path

  # The last modified time of the file
  attr_accessor :mtime

  # The size of the file in bytes
  attr_accessor :size

  # Create an instance of FileStat that will make sure that the instance method
  # +removed?+ returns true when called on it.
  #
  def self.for_removed_path( path )
    ::DirectoryWatcher::FileStat.new(path, nil, nil)
  end

  # Create a new instance of FileStat with the given path, mtime and size
  #
  def initialize( path, mtime, size )
    @path = path
    @mtime = mtime
    @size = size
  end

  # Is the file represented by this FileStat to be considered removed?
  #
  # FileStat doesn't actually go to the file system and check, it assumes if the
  # FileStat was initialized with a nil mtime or a nil size then that data
  # wasn't available, and therefore must indicate that the file is no longer in
  # existence.
  #
  def removed?
    @mtime.nil? || @size.nil?
  end

  # Compare this FileStat to another object.
  #
  # This will only return true when all of the following are true:
  #
  # 1) The other object is also a FileStat object
  # 2) The other object's mtime is equal to this mtime
  # 3) The other object's msize is equal to this size
  #
  def eql?( other )
    return false unless other.instance_of? self.class
    self.mtime == other.mtime and self.size == other.size
  end
  alias :== :eql?

  # Create a nice string based representation of this instance.
  #
  def to_s
    "<#{self.class.name} path: #{path} mtime: #{mtime} size: #{size}>"
  end
end
