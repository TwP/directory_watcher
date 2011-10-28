require 'spec_helper'

describe DirectoryWatcher do
  it "has a version" do
    DirectoryWatcher.version.should =~ /\d\.\d\.\d/
  end
end

describe "Scanners" do
  [ nil, :em, :coolio ].each do |scanner|
#  [ :rev ].each do |scanner|
    context "#{scanner} Scanner" do

      let( :default_options       ) { { :glob => "**/*", :interval => 0.05}                      }
      let( :options               ) { default_options.merge( :scanner => scanner )               }
      let( :options_with_pre_load ) { options.merge( :pre_load => true )                         }
      let( :options_with_stable   ) { options.merge( :stable => 2 )                              }
      let( :options_with_glob     ) { options.merge( :glob => '**/*.42' )                        }
      let( :options_with_persist  ) { options.merge( :persist => scratch_path( 'persist.yml' ) ) }

      let( :directory_watcher               ) { DirectoryWatcher.new( @scratch_dir, options ) }
      let( :directory_watcher_with_pre_load ) { DirectoryWatcher.new( @scratch_dir, options_with_pre_load ) }
      let( :directory_watcher_with_stable   ) { DirectoryWatcher.new( @scratch_dir, options_with_stable   ) }
      let( :directory_watcher_with_glob     ) { DirectoryWatcher.new( @scratch_dir, options_with_glob     ) }
      let( :directory_watcher_with_persist  ) { DirectoryWatcher.new( @scratch_dir, options_with_persist  ) }

      let( :scenario               ) { DirectoryWatcherSpecs::Scenario.new( directory_watcher) }
      let( :scenario_with_pre_load ) { DirectoryWatcherSpecs::Scenario.new( directory_watcher_with_pre_load ) }
      let( :scenario_with_stable   ) { DirectoryWatcherSpecs::Scenario.new( directory_watcher_with_stable   ) }
      let( :scenario_with_glob     ) { DirectoryWatcherSpecs::Scenario.new( directory_watcher_with_glob     ) }
      let( :scenario_with_persist  ) { DirectoryWatcherSpecs::Scenario.new( directory_watcher_with_persist  ) }

      it_should_behave_like 'Scanner'
    end
  end
end

