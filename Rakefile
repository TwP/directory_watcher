
require 'hoe'
require 'directory_watcher'

PKG_VERSION = ENV['VERSION'] || DirectoryWatcher::VERSION

Hoe.new('directory_watcher', PKG_VERSION) do |proj|
  proj.rubyforge_name = 'codeforpeople'
  proj.author = 'Tim Pease'
  proj.email = 'tim.pease@gmail.com'
  proj.url = nil
  proj.extra_deps = []
  proj.summary = 'A class for watching files within a directory and generating events when those files change'
  proj.description = <<-DESC
The directory watcher operates by scanning a directory at some interval and
generating a list of files based on a user supplied glob pattern. As the file
list changes from one interval to the next, events are generated and
dispatched to registered observers. Three types of events are supported --
added, modified, and removed.
  DESC
  proj.changes = <<-CHANGES
Version 1.1.0 / 2007-11-28
  * directory watcher now works with Ruby 1.9

Version 1.0.0 / 2007-08-21
  * added a join method (much like Thread#join)

Version 0.1.4 / 2007-08-20
  * added version information to the class

Version 0.1.3 / 2006-12-07
  * fixed documentation generation bug

Version 0.1.2 / 2006-11-26
  * fixed warnings

Version 0.1.1 / 2006-11-10
  * removed explicit dependency on hoe

Version 0.1.0 / 2006-11-10
  * initial release
  CHANGES
end

# EOF
