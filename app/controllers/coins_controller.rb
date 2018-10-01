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

    create_localized_table_fields

    find_history_data
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

      res = CoinsHistory.update(params[:id].to_i, changes)
      success = !res.count.zero?
      res.clear
    end

    jdata = { meta: { success: success } }
    build_response_json jdata, status: (success ? 200 : 422)
  end

  private

  def params_validate
    params['start'] = (params['start'].present? ? params['start'].to_i : 0)
    params['start'] = 0 if params['start'].negative?

    params['offset'] = (params['offset'].present? ? params['offset'].to_i : 0)
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

  def create_localized_table_fields
    @table_fields = {}
    set_additional_price_column

    [
      'rank',
      'name',
      'mcap',
      @main_price_column,
      'price_avg',
      'price_top_coin',
      'circulating_supply',
      'price_change'
    ].each do |x|
      @table_fields[x] = ((x != @price_adt_col) ? I18n.t("cmarket.table_fields.#{x}") : localized_price_name)
    end
  end

  # Find N-th page of data
  def find_history_data
    history_epoch = params['start']
    history_epoch_offset = (params['offset'].zero? ? 0 : (params['offset'] - 1))

    @currentPage = 1 if history_epoch.zero? && history_epoch_offset.zero?
    @table_data = CoinsHistory.data_of(history_epoch, history_epoch_offset, @main_price_column)

    query_num = (@currentPage.nil? && !@table_data.count.zero? ? @table_data.list.first['query_num'] : nil)
    @currentPage = 0 if @currentPage.nil? && @table_data.count.zero?

    set_pagination(CoinsHistory.pagination_info(query_num))
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
    pparams = url_path_params.dup || {}
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
      param_name = param_name.to_s
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

      key = (avail_change_fields[param_name][:col].blank? ? param_name : avail_change_fields[param_name][:col])
      changes[key] = param_value
    end
    changes
  end

  # Ensure Price column exists in a history table
  # Price USD exists always.
  def ensure_price_column_exist
    return if @main_price_column == 'price_usd'

    if CoinsHistory.field_exist?(@main_price_column)
      @requested_price_currency_absent = false
      return
    end

    # main_price_column doesn't exist in a history table.
    # so use default USD column.
    @main_price_column = price_column_name(false)
    @requested_price_currency_absent = true
  end
end
