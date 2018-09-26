#!/bin/bash -i

bundle exec ruby lib/coins_updater.rb &
bundle exec puma