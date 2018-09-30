require_relative 'db_helper'

module DbModel
  def self.included(base)
  	base.extend ClassMethods
  	base.send :include, InstanceMethods
  end

  module InstanceMethods
    def initialize(data, is_rows)
      @@data = data
      @@is_rows = is_rows
    end

    def clear
      @@data.clear
    end

    def count
      @@is_rows ? @@data.ntuples : @@data.cmd_tuples
    end

    def list
      @@data
    end
  end

  module ClassMethods
    def db=(db_helper)
      @@db ||= db_helper
    end

    def init_table
      db.create_table(table_name, table_init_fields)
    end

    def sequence_name(name)
      table_name + '_' + name.to_s + '_seq'
    end

    def create_sequence(name, initial_value = 0)
      db.create_sequence(sequence_name(name), initial_value)
    end

    def increase_sequence(name)
      db.exec(<<-SQL.squish).clear
        SELECT nextval('#{sequence_name(name)}')
      SQL
    end

    def create_index(name, body)
      db.exec(<<-SQL.squish).clear
        CREATE INDEX IF NOT EXISTS #{name}
        ON #{table_name} (#{body})
      SQL
    end

    def ensure_field_exist(name)
      db.exec(<<-SQL.squish).clear
        ALTER TABLE #{table_name}
        ADD COLUMN IF NOT EXISTS #{name}
        DOUBLE PRECISION NOT NULL DEFAULT 0;
      SQL
    rescue PG::SyntaxError
      begin
        db.exec(<<-SQL.squish).clear
          ALTER TABLE #{table_name}
          ADD COLUMN #{name}
          DOUBLE PRECISION NOT NULL DEFAULT 0;
        SQL
      rescue PG::DuplicateColumn
        nil
      end
    end
    
    def field_exist?(field_name)
      res = db.exec(<<-SQL.squish)
        SELECT TRUE FROM pg_attribute
        WHERE attrelid = (
          SELECT pgc.oid FROM pg_class pgc JOIN pg_namespace pgn ON (pgn.oid = pgc.relnamespace)
          WHERE ((pgn.nspname = CURRENT_SCHEMA()) AND (pgc.relname = '#{table_name}'))
        ) AND (attname = '#{field_name}') AND (NOT attisdropped) AND (attnum > 0)
      SQL
      !res.ntuples.zero?
    end

    private

    def db
      @@db ||= DbHelper.new($logger)
    end

    def query_select(sql_query)
      new(db.exec(sql_query), true)
    end

    def query_change(sql_query)
      new(db.exec(sql_query), false)
    end
  end
end
