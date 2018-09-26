require 'active_support'
require 'active_support/core_ext'
require 'logger'
require 'yaml'
require 'i18n'

require_relative 'db_helper'

module CoinMarket
  class General
    class << self
      def settings
        setts = {}
        YAML.safe_load(database_config_file).each_pair do |k, v|
          setts[k.to_sym] = determine_value(v)
        end

        setts[:I18n_load_path] = Dir['./config/locales/*.yml']
        setts
      end

      def open_log(log_level, log_file_path, log_to_stdout)
        Dir.mkdir('log') unless Dir.exist?('log')
        log_file = File.open(log_file_path, 'a')

        # Set Logger to log into file/stdout or file only
        logger = Logger.new logger_output(log_file, log_to_stdout)
        logger.level = log_level

        logger
      end

      private

      def database_config_file
        File.open(File.join(File.dirname(__FILE__), '../config/settings.yml'))
      end

      def logger_output(log_file, log_to_stdout)
        log_to_stdout ? MultiIO.new(STDOUT, log_file) : log_file
      end

      def determine_value(val)
        %w[none nil].include?(val) ? nil : val
      end
    end
  end

  # Multiple IO for Logger
  class MultiIO
    def initialize(*targets)
      @targets = targets
    end

    def write(*args)
      @targets.each { |t| t.write(*args) }
    end

    def close
      @targets.each(&:close)
    end
  end
end

class String
  def numeric?
    !Float(self).nil? rescue false
  end
end
