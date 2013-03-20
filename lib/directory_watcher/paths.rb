class DirectoryWatcher
  # Paths contains helpful methods to determine paths of files inside the
  # DirectoryWatcher library
  #
  module Paths
    # The root directory of the project is considered the parent directory of
    # the 'lib' directory.
    #
    # Returns The full expanded path of the parent directory of 'lib' going up
    # the path from the current file. Trailing File::SEPARATOR is guaranteed
    #
    def root_dir
      path_parts = ::File.expand_path(__FILE__).split(::File::SEPARATOR)
      lib_index = path_parts.rindex("lib")
      return path_parts[0...lib_index].join(::File::SEPARATOR) + ::File::SEPARATOR
    end

    # Return a path relative to the 'lib' directory in this project
    #
    def lib_path(*args,&block)
      sub_path('lib', *args, &block)
    end

    # Return a path relative to the 'root' directory in the project
    #
    def path(*args,&block)
      sub_path('', *args, &block)
    end

    # Calculate the full expanded path of the item with respect to a sub path of
    # 'root_dir'
    #
    def sub_path(sub,*args,&block)
      rv = ::File.join(root_dir, sub) + ::File::SEPARATOR
      rv = ::File.join(rv, *args) if args
      if block
        with_load_path( rv ) do
          rv = block.call
        end
      end
      return rv
    end

    # Execute a block in the context of a path added to $LOAD_PATH
    #
    def with_load_path(path, &block)
      $LOAD_PATH.unshift path
      block.call
    ensure
      $LOAD_PATH.shift
    end

    extend self
  end
end
