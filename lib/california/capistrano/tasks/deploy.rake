# The basic capistrano framework provides us with a certain order of tasks when you run "rake deploy".
# See https://github.com/capistrano/capistrano/blob/master/lib/capistrano/tasks/framework.rake
# In the code below we hook in into those tasks provided by the deploy framework.

namespace :deploy do

  # –––––––––––––––––
  # Updating the code
  # –––––––––––––––––

  task :updating do
    logger.info 'Updating the repository...'

    on roles :app do
      as fetch(:application) do
        within fetch(:deploy_to) do

          # Remembering which revision we had before making any changes.
          set :previous_revision, capture(:git, 'rev-parse', 'HEAD')

          # Updating the code.
          execute :git, :reset, '--hard'
          execute :git, :fetch, :origin
          execute :git, :checkout, '--force', "origin/#{fetch(:branch)}"

          # The update went well so let's persist the revision change.
          # Note: We use ruby because there is no bash command that can write to files *without I/O redirection*.
          set :current_revision, capture(:git, 'rev-parse', 'HEAD')
          execute :ruby, '-e', %("File.write :REVISION.to_s,      %|#{fetch(:current_revision)}|"  )
          execute :ruby, '-e', %("File.write :PREV_REVISION.to_s, %|#{fetch(:previous_revision)}|" )
          execute :ruby, '-e', %("File.write :BRANCH.to_s,        %|#{fetch(:branch)}|"            )
        end
      end
    end
  end

  # ––––––––––––––
  # Set robots.txt
  # ––––––––––––––

  desc 'Disallow robots unless deploying to production.'
  task :disallow_robots do
    next if fetch(:stage).to_s == 'production'
    logger.info "Overriding robots.txt for environment #{fetch(:stage)}..."

    on roles :app do
      as fetch(:application) do
        within File.join(fetch(:deploy_to), 'public') do
          execute :echo, %("User-agent: *\nDisallow: /\n" > robots.txt)
        end
      end
    end
  end

  # –––––––––––––––
  # Running Bundler
  # –––––––––––––––

  task :updated do
    if fetch(:skip_bundler)
      logger.info 'Skipping Bundler...'
    else
      logger.info 'Running Bundler...'

      on roles :app do
        as fetch(:application) do
          within fetch(:deploy_to) do

            # Running Bundler.
            core_count = capture(:nproc).chomp
            execute :bundle, :install, '--deployment', '--quiet', '--without', 'development', 'test', '--jobs', core_count
          end
        end
      end
    end
  end

  # ––––––––––––––––––
  # Restarting the app
  # ––––––––––––––––––

  task :publishing do
    if fetch(:skip_restart)
      logger.info 'Skipping Restart...'
    else

      on roles :app do
        as fetch(:application) do

          if fetch(:restart_strategy) == 'restart.txt'
            logger.info 'Restarting the app via restart.txt...'
            within File.join(fetch(:deploy_to), 'tmp') do
              execute :touch, 'restart.txt'
            end

          else
            logger.info 'Restarting the app via passenger-config...'
            execute 'passenger-config', 'restart-app', fetch(:deploy_to)
          end
        end
      end
    end
  end

  # ––––––––––––––––––––––––––
  # Persisting the deploy time
  # ––––––––––––––––––––––––––

  task :finishing do
    logger.info 'Persisting the deploy time...'

    on roles :app do
      as fetch(:application) do
        within fetch(:deploy_to) do

          execute :ruby, '-e', %("File.write :DEPLOYED_AT.to_s, Time.now")
        end
      end
    end
  end

  task :finished do
    logger.info 'Congratulations! ¯\_(ツ)_/¯'
  end

  task :failed do
    logger.info 'Oh no, the deployment failed'
  end

end
