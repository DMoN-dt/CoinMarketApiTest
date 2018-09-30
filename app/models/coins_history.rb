class CoinsHistory
  include DbModel

  class << self
    def table_name
      $tablename_coins_history || 'coins_history'
    end

    def create(data_fields, data_values)
      query_change(<<-SQL.squish)
        INSERT INTO #{table_name} (#{data_fields})
        VALUES #{data_values}
      SQL
    end

    def update(id, changes)
      query_change(<<-SQL.squish)
        UPDATE #{table_name}
        SET #{changes.map { |k, v| "#{k} = '#{v}'" }.join(', ')}
        WHERE (id = #{id.to_i})
      SQL
    end

    def pagination_info(query_num)
      sql = <<-SQL.squish
        SELECT COUNT(*) AS count
          FROM (SELECT 1 FROM #{table_name} GROUP BY query_num) AS tbl
        UNION ALL
        SELECT MAX(query_num) AS count
          FROM #{table_name}
      SQL
      return db.exec(sql) unless query_num

      sql += <<-SQL.squish.prepend(' ')
        UNION ALL SELECT COUNT(*) AS count
        FROM (
          SELECT 1 FROM #{table_name}
          WHERE (query_num > #{query_num})
          GROUP BY query_num
        ) AS tbl
      SQL

      db.exec(sql)
    end

    def data_of(history_epoch, history_epoch_offset, main_price_column)
      query_select(<<-SQL.squish)
        SELECT cht.id, coins.name, coins.symbol, cht.rank,
          cht.#{main_price_column},
          ROUND(cht.#{main_price_column} * cht.circulating_supply) AS mcap,
          cht.circulating_supply,
          cht.updated_at,
          cht.query_num,

          CASE WHEN (top_price.top_coin_price != 0) THEN ROUND((cht.#{main_price_column} / top_price.top_coin_price)::numeric, 10) ELSE NULL END AS price_top_coin,
          (
            SELECT ROUND(AVG(#{main_price_column})::numeric, 5)
            FROM #{table_name} AS hst
            WHERE (hst.coin_id = cht.coin_id) AND (hst.updated_at > (cht.updated_at - interval '24 hours'))
          ) AS price_avg,
        
          CASE WHEN (old_price.price != 0) THEN ROUND((100 * (cht.#{main_price_column} - old_price.price) / old_price.price)::numeric, 2) ELSE NULL END AS price_change

        FROM #{table_name} AS cht
        INNER JOIN #{Coin.table_name} coins ON (coins.id = cht.coin_id),
        LATERAL (
          SELECT COALESCE(#{main_price_column}, 0) AS price
          FROM #{table_name} AS hst
          WHERE (hst.coin_id = cht.coin_id) AND (hst.updated_at > (cht.updated_at - interval '24 hours')) AND (hst.#{main_price_column} != 0)
          ORDER BY updated_at ASC
          LIMIT 1
        ) AS old_price,
        (
          SELECT COALESCE(#{main_price_column}, 0) AS top_coin_price
          FROM #{table_name}
          ORDER BY query_num DESC, rank ASC
          LIMIT 1
        ) AS top_price
        WHERE cht.query_num = (#{query_num_of(history_epoch, history_epoch_offset)})
        ORDER BY cht.rank
      SQL
    end

    private

    def table_init_fields
      [
        { name: 'id', type: 'integer', primary: true, null: false, default: "nextval('#{sequence_name(:id)}')" },
        { name: 'query_num', type: 'integer', null: false, default: "currval('#{sequence_name(:query_num)}')" }, # Request number
        { name: 'coin_id', type: 'integer', null: false }, # Coin ID
        { name: 'rank', type: 'smallint', null: false, default: 0 }, # Coin rank
        { name: 'price_usd', type: 'double precision', null: false, default: 0.0 }, # Price in USD
        { name: 'circulating_supply', type: 'double precision', null: false, default: 0.0 }, # Circulating Supply
        { name: 'updated_at', type: 'timestamp with time zone', null: false, default: 'NOW()' } # Request timestamp
      ]
    end
    
    def query_num_of(history_epoch, history_epoch_offset)
      if history_epoch.zero?
        if history_epoch_offset.zero?
          sql = <<-SQL.squish
            SELECT MAX(query_num)
            FROM #{table_name}
          SQL
          return sql
        end

        sql = <<-SQL.squish
          SELECT query_num
          FROM #{table_name}
          GROUP BY query_num
          ORDER BY query_num
          DESC OFFSET #{history_epoch_offset}
          LIMIT 1
        SQL
        return sql
      end

      <<-SQL.squish
        SELECT query_num
        FROM #{table_name}
        WHERE (query_num <= #{history_epoch})
        GROUP BY query_num
        ORDER BY query_num
        DESC OFFSET #{history_epoch_offset}
        LIMIT 1
      SQL
    end
  end
end
