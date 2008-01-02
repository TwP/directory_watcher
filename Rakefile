# $Id$

load 'tasks/setup.rb'
ensure_in_path 'lib'
require 'directory_watcher'

task :default => 'spec:run'

PROJ.name = 'directory_watcher'
PROJ.summary = 'A class for watching files within a directory and generating events when those files change'
PROJ.authors = 'Tim Pease'
PROJ.email = 'tim.pease@gmail.com'
PROJ.url = 'http://codeforpeople.rubyforge.org/directory_watcher'
PROJ.description = paragraphs_of('README.txt', 1).join("\n\n")
PROJ.changes = paragraphs_of('History.txt', 0..1).join("\n\n")
PROJ.rubyforge_name = 'codeforpeople'
PROJ.rdoc_remote_dir = 'directory_watcher'
PROJ.version = DirectoryWatcher::VERSION

# EOF
