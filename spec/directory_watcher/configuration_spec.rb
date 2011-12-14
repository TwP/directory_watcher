require 'spec_helper'

describe DirectoryWatcher::Configuration do

  it 'should expand passed ignore glob path' do 
    config = DirectoryWatcher::Configuration.new(dir: @scratch_dir, ignore_glob: '**/*.rb')

    config.ignore_glob.should == [File.join(@scratch_dir, '**/*.rb')]
  end

  it 'should expand passed array of ignore globs' do 
    config = DirectoryWatcher::Configuration.new(dir: @scratch_dir, ignore_glob: %w(**/*.rb *.txt))

    config.ignore_glob.should == [File.join(@scratch_dir, '**/*.rb'), File.join(@scratch_dir, '*.txt')]
  end

end
