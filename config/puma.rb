workers 2
threads_count = 5

threads threads_count, threads_count

preload_app!

rackup      DefaultRackup
port        ENV['PUMA_PORT'] || 3000
environment ENV['RACK_ENV']  || 'development'
