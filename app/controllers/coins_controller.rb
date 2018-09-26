require_relative 'application_controller.rb'

class CoinsController < ApplicationController
  def index
    params_validate

    # Number of central page-links in navigation panel
    @numbersCount = 5

    # Choose of price column to use:
    # a requested in 'currency' param or default USD.
    @main_price_column = price_column_name
    ensure_price_column_exist

    # Prepare Columns for TableView
    table_columns = [
      'rank',
      'name',
      'mcap',
      @main_price_column,
      'price_avg',
      'price_top_coin',
      'circulating_supply',
      'price_change'
    ]

    set_additional_price_column

    @table_fields = {}
    table_columns.each do |x|
      @table_fields[x] = ((x != @price_adt_col) ? I18n.t("cmarket.table_fields.#{x}") : localized_price_name)
    end

    # Find N-th page of data
    history_epoch = params['start']
    history_epoch_offset = params['offset']

    @table_data = query_db_data(history_epoch, history_epoch_offset)

    # Number of Rows fetched
    @table_data_count = @table_data ? @table_data.ntuples : 0

    set_pagination(db_exec(sql_current_page_filter))

    build_response render
  end

  def update
    success = false

    public_avail_change_fields = {
      price_column_name => { null: false, minimum: 0 },
      'circulating_supply' => { null: false, minimum: 0 }
    }

    if params[:id].present? && params[:id].numeric?
      changes = prepare_changes(public_avail_change_fields)

      res = db_exec(<<-SQL.squish)
        UPDATE coins_history
        SET #{changes.map { |k, v| "#{k} = '#{v}'" }.join(', ')}
        WHERE (id = #{params[:id].to_i})
      SQL

      success = (res.cmd_tuples != 0)
      res.clear
    end

    jdata = { meta: { success: success } }
    build_response_json jdata, status: (success ? 200 : 422)
  end

  private

  def params_validate
    params['start'] = (params['start'].present? ? params['start'].to_i : 0)
    params['start'] = 0 if params['start'].negative?

    params['offset'] = (params['offset'].present? ? (params['offset'].to_i - 1) : 0)
    params['offset'] = 0 if params['offset'].negative?
  end

  def query_db_data(history_epoch, history_epoch_offset)
    db_exec(
      sql_data_requested(
        sql_query_num_filter(history_epoch, history_epoch_offset)
      )
    )
  end

  # Select Existing Price_Currency column for Price, Price Avg, Price Change and Price TOP-coin calculation
  def price_column_name(use_params = true)
    if use_params && params['currency'].present?
      pcheck = params['currency'].upcase
      if ['USD', settings[:price_additional_currency].upcase].include?(pcheck)
        return 'price_' + params['currency'].downcase
      end
    end

    params['currency'] = 'USD'
    'price_usd'
  end

  def set_additional_price_column
    if settings[:price_additional_currency].blank?
      @price_adt_col = nil
      return
    end

    @price_adt_name = settings[:price_additional_currency].upcase
    @price_adt_col  = 'price_' + settings[:price_additional_currency].downcase
  end

  def localized_price_name
    I18n.t('cmarket.table_fields.price') + ", #{@price_adt_name}"
  end

  def set_pagination(res)
    return if res.nil?
    @totalPages   =  res[0]['count'].to_i
    @offset_start =  res[1]['count'].to_i
    @currentPage  = (res[2]['count'].to_i + 1) if @currentPage.nil?
    res.clear

    @startPage = pagination_startPage
    @endPage   = pagination_endPage
  end

  def pagination_link(page)
    pparams = url_path_params.dup
    pparams['start']  = @offset_start
    pparams['offset'] = page
    pparams.to_query.prepend('?')
  end

  def pagination_startPage
    if @currentPage > ((@numbersCount / 2).floor + 1) && @totalPages > @numbersCount
      sp = @currentPage - (@numbersCount / 2).floor
    else
      sp = 1
    end

    if @currentPage > (@totalPages - (@numbersCount / 2).floor) || (sp + @numbersCount-1) > @totalPages
      sp = (@totalPages - @numbersCount + 1) if (@totalPages - @numbersCount + 1) >= 1
    end
    sp
  end

  def pagination_endPage
    if @currentPage <= (@totalPages - (@numbersCount / 2).floor) && (@startPage + @numbersCount-1) <= @totalPages
      return @startPage + @numbersCount - 1
    end
    @totalPages
  end

  def prepare_changes(avail_change_fields)
    changes = {}

    params.each do |param_name, param_value|
      next if avail_change_fields[param_name].nil?

      if !param_value.nil? && !avail_change_fields[param_name][:minimum].nil? && (param_value.to_f < avail_change_fields[param_name][:minimum])
        param_value = avail_change_fields[param_name][:minimum]

      elsif param_value.nil? && (avail_change_fields[param_name][:null] != true)
        if avail_change_fields[param_name][:default].nil?
          if avail_change_fields[param_name][:minimum].nil?
            param_value = 0
          else
            param_value = avail_change_fields[param_name][:minimum]
          end
        else
          param_value = avail_change_fields[param_name][:default]
        end
      end

      if param_value.present?
        if avail_change_fields[param_name][:integer] == true
          param_value = param_value.to_i
        elsif avail_change_fields[param_name][:float] == true
          param_value = param_value.to_f
        elsif !avail_change_fields[:minimum].nil? || !avail_change_fields[:maximum].nil?
          if avail_change_fields[:minimum].is_a?(Float) || avail_change_fields[:maximum].is_a?(Float)
            param_value = param_value.to_f
          else
            param_value = param_value.to_i
          end
        else
          if !avail_change_fields[:limit].nil? && param_value.length > avail_change_fields[:limit]
            param_value = param_value[0, avail_change_fields[:limit]]
          end

          if param_value.is_a?(String)
            param_value.gsub!("'", "\'")
            param_value.gsub!('"', '\"')
          end
        end
      end

      changes[ avail_change_fields[param_name][:col].blank? ? param_name : avail_change_fields[param_name][:col] ] = param_value
    end
    changes
  end

  # Determine current page position in entire history
  def sql_current_page_filter
    filter_sql = <<-SQL.squish
      SELECT COUNT(*) AS count
        FROM (SELECT 1 FROM coins_history GROUP BY query_num) AS tbl
      UNION ALL
      SELECT MAX(query_num) AS count
        FROM coins_history
    SQL

    if @currentPage.nil?
      if @table_data_count.zero?
        @currentPage = 0
      else
        filter_sql += <<-SQL.squish.prepend(' ')
          UNION ALL SELECT COUNT(*) AS count
          FROM (
            SELECT 1 FROM coins_history
            WHERE (query_num > #{@table_data.first['query_num']})
            GROUP BY query_num
          ) AS tbl
        SQL
      end
    end
    filter_sql
  end

  def sql_query_num_filter(history_epoch, history_epoch_offset)
    if history_epoch.zero?
      if history_epoch_offset.zero?
        filter_sql = <<-SQL.squish
          SELECT MAX(query_num)
          FROM coins_history
        SQL
        @currentPage = 1
        return filter_sql
      end

      filter_sql = <<-SQL.squish
        SELECT query_num
        FROM coins_history
        GROUP BY query_num
        ORDER BY query_num
        DESC OFFSET #{history_epoch_offset}
        LIMIT 1
      SQL
      return filter_sql
    end

    <<-SQL.squish
      SELECT query_num
      FROM coins_history
      WHERE (query_num <= #{history_epoch})
      GROUP BY query_num
      ORDER BY query_num
      DESC OFFSET #{history_epoch_offset}
      LIMIT 1
    SQL
  end

  def sql_data_requested(query_num_filter_sql)
    <<-SQL.squish
      SELECT cht.id, coins.name, coins.symbol, cht.rank,
        cht.#{@main_price_column},
        ROUND(cht.#{@main_price_column} * cht.circulating_supply) AS mcap,
        cht.circulating_supply,
        cht.updated_at,
        cht.query_num,

        CASE WHEN (top_price.top_coin_price != 0) THEN ROUND((cht.#{@main_price_column} / top_price.top_coin_price)::numeric, 10) ELSE NULL END AS price_top_coin,
        (
          SELECT ROUND(AVG(#{@main_price_column})::numeric, 5)
          FROM coins_history AS hst
          WHERE (hst.coin_id = cht.coin_id) AND (hst.updated_at > (cht.updated_at - interval '24 hours'))
        ) AS price_avg,

        CASE WHEN (old_price.price != 0) THEN ROUND((100 * (cht.#{@main_price_column} - old_price.price) / old_price.price)::numeric, 2) ELSE NULL END AS price_change

      FROM coins_history AS cht
      INNER JOIN coins ON (coins.id = cht.coin_id),
      LATERAL (
        SELECT COALESCE(#{@main_price_column}, 0) AS price
        FROM coins_history AS hst
        WHERE (hst.coin_id = cht.coin_id) AND (hst.updated_at > (cht.updated_at - interval '24 hours')) AND (hst.#{@main_price_column} != 0)
        ORDER BY updated_at ASC
        LIMIT 1
      ) AS old_price,
      (
        SELECT COALESCE(#{@main_price_column}, 0) AS top_coin_price
        FROM coins_history
        ORDER BY query_num DESC, rank ASC
        LIMIT 1
      ) AS top_price
      WHERE cht.query_num = (#{query_num_filter_sql})
      ORDER BY cht.rank
    SQL
  end

  def table_price_column_exist?
    res = db_exec(<<-SQL.squish)
      SELECT TRUE FROM pg_attribute
      WHERE attrelid = (
        SELECT pgc.oid FROM pg_class pgc JOIN pg_namespace pgn ON (pgn.oid = pgc.relnamespace)
        WHERE ((pgn.nspname = CURRENT_SCHEMA()) AND (pgc.relname = 'coins_history'))
      ) AND (attname = '#{@main_price_column}') AND (NOT attisdropped) AND (attnum > 0)
    SQL
    !res.ntuples.zero?
  end

  # Ensure Price column exists in a history table
  # Price USD exists always.
  def ensure_price_column_exist
    return if @main_price_column == 'price_usd'

    if table_price_column_exist?
      @requested_price_currency_absent = false
      return
    end

    # main_price_column doesn't exist in a history table.
    # so use default USD column.
    @main_price_column = price_column_name(false)
    @requested_price_currency_absent = true
  end
end
