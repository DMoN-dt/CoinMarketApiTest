#!/bin/bash -i

if [ ! -f "procfile" ]; then
	echo "updater_worker: `which rbenv` exec bundle exec ruby lib/coins_updater.rb - stdout_sync" > procfile
	echo "web_server: `which rbenv` exec bundle exec puma -p 3000" >> procfile
fi

if [ -f "procfile" ]; then
	bundle install
	foreman start -f procfile
else
	echo "ERROR: Unable to find or create Procfile for Foreman !"
fi