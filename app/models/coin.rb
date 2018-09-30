class Coin
  include DbModel

  class << self
    def first(limit_num = 1)
      query_select(<<-SQL.squish)
        SELECT id, symbol, mcap_id
        FROM #{table_name}
        LIMIT #{limit_num}
      SQL
    end

    def create(data)
      query_change(<<-SQL.squish)
        INSERT INTO #{table_name} (name, symbol, mcap_id)
        VALUES #{data_to_values(data)}
      SQL
    end

    def table_name
      $tablename_coins || 'coins'
    end

    private

    def table_init_fields
      [
        { name: 'id', type: 'integer', primary: true, null: false, default: "nextval('#{sequence_name(:id)}')" },
        { name: 'name', type: 'character varying(20)', null: false }, # Coin name
        { name: 'symbol', type: 'character varying(20)', null: false }, # Coin symbol (BTC, ETH etc.)
        { name: 'mcap_id', type: 'character varying(20)', null: false } # Coin ID on market
      ]
    end

    def data_to_values(data)
      data.map { |v| "(#{values_to_string(v)})" }.join(',')
    end

    def values_to_string(val)
      [
        val['name'],
        val['symbol'],
        val['id']
      ].map { |v| "'#{v}'" }.join(',')
    end
  end
end
