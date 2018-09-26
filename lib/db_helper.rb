require 'pg'

module CoinMarket
  # Database Object with helpers
  class DbHelper
    attr_reader :db_object

    def initialize(logger = nil)
      @logger = logger
      initialize_database!
    end

    def initialize_database!
      connect_database if load_config
    end

    def create_table(table_name, columns, drop_table = false)
      return nil if db_object.nil? || table_name.blank? || columns.blank?

      exec(<<-SQL.squish).clear if drop_table
        DROP TABLE IF EXISTS #{table_name}
      SQL

      exec(<<-SQL.squish).clear
        CREATE TABLE IF NOT EXISTS #{table_name} (
          #{columns.map! { |col| column_parameters(col) }.join(', ')}
        )
      SQL
    end

    def create_sequence(seq_name, start_val = 0, step_val = 1, drop_seq = false)
      return nil if db_object.nil? || seq_name.blank?

      exec(<<-SQL.squish).clear if drop_seq
        DROP SEQUENCE IF EXISTS #{seq_name}
      SQL

      exec(<<-SQL.squish).clear
        CREATE SEQUENCE IF NOT EXISTS #{seq_name}
        INCREMENT BY #{step_val}
        START #{start_val}
        MINVALUE #{start_val}
      SQL
    end

    def exec(sql_query_str)
      return nil if db_object.nil? || sql_query_str.blank?
      begin
        db_object.exec sql_query_str
      rescue PG::UnableToSend => e
        log_error(e)
        db_object.exec(sql_query_str) unless initialize_database!.nil?
      end
    end

    private

    def database_config_file
      File.open(File.join(File.dirname(__FILE__), '../config/database.yml'))
    end

    def load_config
      @db_config ||= YAML.safe_load(database_config_file)
      return true unless @db_config.blank? && !@logger.nil?

      log_error 'Unable to load database configuration'
      false
    end

    def connect_database
      if @db_config['adapter'] == 'postgresql'
        connect_pg!
        return
      end

      log_error 'Unknown database adapter !'
      @db_object = nil
    end

    def connect_pg!
      @db_object = PG.connect(
        host: @db_config['host'],
        port: @db_config['port'],
        dbname: @db_config['database'],
        user: @db_config['username'],
        password: @db_config['password']
      )
    end

    def log_error(message)
      @logger&.error(message)
    end

    def column_parameters(col)
      [
        col[:name],
        col[:type],
        col_param_null(col),
        col_param_default(col),
        col_param_primary(col)
      ].join(' ')
    end

    def col_param_default(column)
      column[:default].nil? ? '' : "DEFAULT #{column[:default]}"
    end

    def col_param_null(column)
      column[:null].nil? || column[:null] ? '' : 'NOT NULL'
    end

    def col_param_primary(column)
      column[:primary] ? 'PRIMARY KEY' : ''
    end
  end
end
