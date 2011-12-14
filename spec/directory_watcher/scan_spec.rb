require 'spec_helper'

describe DirectoryWatcher::Scan do

  it 'should ignore file matched by ignore_glob' do
    scan = DirectoryWatcher::Scan.new(scratch_path('*'), [scratch_path('*.rb'), scratch_path('*.py')])
    touch(scratch_path('file1.rb'))
    touch(scratch_path('file2.py'))
    touch(scratch_path('file3.txt'))

    scan.run
    scan.results.size.should == 1
  end

  it 'should ignore nil pased as ignore_glob' do
    scan = DirectoryWatcher::Scan.new(scratch_path('*'), nil)
    touch(scratch_path('file1.rb'))
    touch(scratch_path('file2.py'))
    touch(scratch_path('file3.txt'))

    scan.run
    scan.results.size.should == 3
  end

end
