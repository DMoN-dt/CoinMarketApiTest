#!/usr/bin/ruby

if ARGV.length.positive? && ARGV.include?('stdout_sync')
  # Disable stdout buffering enabled by default.
  # This needs for Foreman correct output.
  $stdout.sync = true

  puts 'STDOUT Buffering disabled.'
end

require_relative 'coins_general'

model_files = File.expand_path('../../app/models/*.rb', __FILE__)
Dir.glob(model_files).each { |file| require(file) }

require 'net/http'
require 'uri'

module CoinMarket
  class Updater
    attr_reader :logger
    attr_reader :settings
    attr_reader :coins_num
    attr_reader :coins_num_more
    attr_reader :price_additional_currency

    # Do the Job
    #
    def start
      unless db_ready?
        logger.info('Unable to start without connection to Database !')
        return
      end

      logger.info 'Starting...'
      query_coinmarketcap
    end

    # General initializations
    #
    def initialize(iparams = {})
      @settings = General.settings

      default_params = {
        coins_num: 20,
        price_additional_currency: settings[:price_additional_currency],
        log_level: Logger::ERROR,
        log_to_stdout: false,
        log_file_path: settings[:updater_log_file_path]
      }
      default_params.each_key { |key| iparams[key] = default_params[key] unless iparams.key?(key) }

      @logger = General.open_log(iparams[:log_level], iparams[:log_file_path], iparams[:log_to_stdout])
      $logger = @logger

      initialize_i18n

      return unless db_ready?

      @coins_num = iparams[:coins_num]
      
      # Add a reserve for case the low-price currencies
      # lose positions temporarily and get out of the coins_num limit
      @coins_num_more = 3

      @price_additional_currency = iparams[:price_additional_currency]

      $tablename_coins = settings[:tablename_coins]
      $tablename_coins_history = settings[:tablename_coins_history]

      initialize_database_tables!
    end

    def initialize_database_tables!
      logger.info('Checking tables initialization...')

      create_database_sequences
      create_database_tables
      add_table_price_column
    end

    # Query of CoinMarketCap Public API for actual rates information
    #
    def query_coinmarketcap
      logger.debug 'Querying CoinMarketCap...'

      rparams = { limit: coins_num + coins_num_more }
      if price_additional_currency.present?
        rparams[:convert] = price_additional_currency
      end

      response = fetch_url('https://api.coinmarketcap.com/v1/ticker/', :get, rparams)
      unless response_ok?(response)
        log_unsuccessful(response)
        return
      end

      data_arr = JSON.parse(response[:body])
      unless data_arr.is_a?(Array)
        logger.debug "RESPONSE BODY: #{response[:body]}"
        logger.error('Response from CoinMarketCap is not an Array!')
        return
      end

      logger.debug "RESPONSE ARRAY: #{data_arr}"

      unless data_arr.length
        logger.error('Received response array is Empty!')
        return
      end

      logger.info 'CoinMarketCap queried Successfully'

      # Look for coins existing in DB
      coins = Coin.first(coins_num)

      # Is it a first query and there is nothing in DB ?
      if coins.count.zero?
        logger.info "Coins table is empty! Let's fill it with a maximum of #{coins_num} coins received."

        coins.clear

        res = Coin.create(data_arr[0, coins_num])

        logger.info "Inserted #{res.count} coins."
        res.clear

        coins = Coin.first(coins_num)
      end

      known_coins = coins.list
      known_coins_count = coins.count

      # Fill a new history data
      coins_info = []

      price_add_col = (price_additional_currency.present? ? ('price_' + price_additional_currency.downcase) : nil)

      known_coins.each do |coin|
        found = data_arr.select { |x| x['symbol'] == coin['symbol'] }.first
        next if found.blank?

        store_coin_info(coin, found, coins_info, price_add_col)
      end

      if known_coins_count > coins_info.length
        coins_wo_data = known_coins.map { |x| x['id'] } - coins_info.map { |x| x[:coin_id] }

        coins_wo_data = known_coins.select { |x| coins_wo_data.include?(x['id']) }

        logger.warn "Some coins are absent in TOP #{coins_num + coins_num_more} List. Let's try to query each one separately..."
        logger.warn "Absent coins are #{coins_wo_data.map { |x| x['mcap_id'] }}"

        found_coins = []
        rparams = {}
        rparams[:convert] = price_additional_currency if price_additional_currency.present?

        coins_wo_data.each do |coin|
          response = fetch_url("https://api.coinmarketcap.com/v1/ticker/#{coin['mcap_id']}/", :get, rparams)
          next unless response_ok?(response)

          found = data_of(response[:body])
          next if found.nil?

          found_coins << found['id']
          store_coin_info(coin, found, coins_info, price_add_col, false)
        end

        if known_coins_count >= coins_info.length
          coins_wo_data = coins_wo_data.map { |x| x['mcap_id'] } - found_coins
          logger.error "Unable to find data for #{coins_wo_data.length} coins: #{coins_wo_data}"
        end
      end

      # Save to DB
      if coins_info.length
        CoinsHistory.increase_sequence(:query_num)

        response = CoinsHistory.create(data_fields(coins_info), data_values(coins_info))
        if response.count == coins_info.length
          logger.debug "#{response.count} rows Inserted into coins_history Successfully"
        else
          logger.error 'Insert of new coins history is Failed'
        end

        response.clear
      end

      known_coins.clear
    end

    def sleep_for(seconds_interval = settings[:sleep_for_minutes] * 60)
      logger.info "Query will start again in #{seconds_interval} seconds..."
      sleep(seconds_interval)
    end

    private

    def db_ready?
      @db ||= DbHelper.new(logger)
      return !@db.nil?
    end

    def initialize_i18n
      I18n.load_path = settings[:I18n_load_path]
      I18n.available_locales = settings[:I18n_available_locales]
      I18n.default_locale = settings[:I18n_default_locale]
      I18n.backend.load_translations
    end

    def create_database_sequences
      Coin.create_sequence('id', 1)
      CoinsHistory.create_sequence('id', 1)
      CoinsHistory.create_sequence('query_num')
    end

    def create_database_tables
      Coin.init_table
      CoinsHistory.init_table
      CoinsHistory.create_index(:query_num_idx, 'query_num DESC')
    end

    # Add column with additional currency of price if required
    def add_table_price_column
      return if price_additional_currency.blank?
      price_column = 'price_' + price_additional_currency.downcase

      # Ensure the column price_XXXX exists in a history table
      CoinsHistory.ensure_field_exist(price_column)
    end

    def response_ok?(response)
      response[:status] == 200 && response[:body].present?
    end

    def log_unsuccessful(response)
      logger.error(I18n.t('dmon_errors.general.information_not_received'))
      logger.error("URI HOST / SCHEME: #{response[:uri_host]} / #{response[:uri_scheme]}")
      logger.error("URI REQUEST PATH: #{response[:uri_request_path]}")
      logger.error("ERROR: #{response[:error]}")
      logger.error("ERROR DESCRIPTION: #{response[:error_desc]}")
      logger.error("ERROR REMOTE RESPONSE: #{response[:error_server_desc]}")
      logger.debug "RESPONSE: #{response}"
    end

    def data_of(body)
      parsed = JSON.parse(body)
      if parsed.is_a?(Array) && parsed.first['id'] == coin['mcap_id']
        return parsed.first
      end
      nil
    end

    def data_exist?(found, column)
      !column.nil? && found[column].present?
    end

    def store_coin_info(coin, found, coins_info, price_add_col, known_coin = true)
      data = {
        coin_id: coin['id'],
        rank: found['rank'],
        price_usd: found['price_usd'],
        circulating_supply: found['available_supply'],
      }

      if data_exist?(found, price_add_col)
        additional_col_storage = known_coin ? data : coins_info
        additional_col_storage[price_add_col] = found[price_add_col]
      end

      coins_info << data
    end

    def data_fields(coins_info)
      coins_info.first.keys.join(', ')
    end

    def data_values(coins_info)
      coins_info.map { |x| "(#{x.values.join(', ')})" }.join(', ')
    end

    def fetch_url(url, method = :get, params = nil, type_want = :json, raise_errors = false)
      failed = false
      err_server_msg = nil
      err_desc = nil
      ret = {}
      host_addr = ''

      if /\A((https:)?\/\/)?.+\z/.match?(url)
        http_ensure_ssl(url)
        uri = URI(url)
        begin
          host_addr = uri.host + ':' + uri.port.to_s

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri_https?(uri)) do |http|
            begin
              request = http_request_create(uri, method, params)
            rescue NoMethodError
              err_desc = I18n.t('dmon_errors.tcp.bad_url')
            end

            if request
              response = http.request(request)
              failure = http_response_validate(response, type_want, ret)
              failed, err_server_msg, err_desc = failure
            end
          end
        rescue SocketError => e
          logger.error("#{self.class.name} Timeout for #{url}: #{e.message}")
          failed = true

          if e.message.include? 'getaddrinfo: Name or service not known'
            err_desc = I18n.t('dmon_errors.socket_errors.name_or_service_is_unknown')
          end
        rescue Errno::ECONNREFUSED
          err_desc = I18n.t('dmon_errors.tcp.connection_refused')
        end
      else
        err_desc = I18n.t('dmon_errors.tcp.not_https_pattern')
      end

      if failed || err_desc
        ret[:error] = I18n.t('dmon_errors.socket_errors.failed_to_open_tcp_connection_to', host: host_addr)
        ret[:error_desc] = err_desc
        ret[:error_server_desc] = err_server_msg
        ret[:uri_host] = host_addr
        ret[:uri_scheme] = uri.scheme
        ret[:uri_request_path] = uri.request_uri

        if raise_errors
          raise(StandardError, ret[:error] + " (#{err_server_msg} #{err_desc})")
        end
      end
      ret
    end

    def i18n_key_http_status(status_code)
      if I18n.exists?("dmon_errors.tcp.http_status_#{status_code}")
        return "http_status_#{status_code}"
      end
      'http_status_code'
    end

    def http_ensure_ssl(url)
      return if url.start_with?('https:')
      url.prepend(url.start_with?('//') ? 'https:' : 'https://')
    end

    def uri_https?(uri)
      uri.scheme == 'https'
    end

    def http_request_create(uri, method, params)
      if method == :post
        request = Net::HTTP::Post.new(uri.request_uri)
        request.set_form_data(params) if params.present? && request
        return request
      end

      Net::HTTP::Get.new http_uri_with_params(uri, params)
    end

    def http_params_to_query(params)
      params.present? ? params.to_query.prepend('?') : ''
    end

    def http_uri_with_params(uri, params)
      uri.request_uri + http_params_to_query(params)
    end

    def http_response_validate(response, type_want, ret)
      failed = false
      err_server_msg = nil

      case response
      when Net::HTTPSuccess
        http_process_success_response(response, type_want, ret)
      when Net::HTTPResponse
        err_server_msg = http_process_response_code(response, ret)
      else
        failed = true
      end

      err_desc = http_invalid_status_descr(ret[:status])

      [failed, err_server_msg, err_desc]
    end

    def http_response_invalid_html?(response, type_want)
      (type_want == :html) && !response.content_type.include?('text/html')
    end

    def http_response_invalid_json?(response, type_want)
      (type_want == :json) && !response.content_type.include?('/json')
    end

    def http_response_invalid?(response, type_want)
      (
        http_response_invalid_html?(response, type_want) ||
        http_response_invalid_json?(response, type_want)
      )
    end

    def http_process_success_response(response, type_want, ret)
      ret[:status] = response.code.to_i
      ret[:status] = 415 if http_response_invalid?(response, type_want)

      response.read_body
      ret[:body] = response.body
    end

    def http_process_response_code(response, ret)
      ret[:status] = response.code.to_i
      return nil if response.message.blank?

      response.message.concat('. ')
    end

    def http_invalid_status_descr(http_status_code)
      return nil if http_status_code >= 200 && http_status_code < 300
      I18n.t(
        i18n_key_http_status(ret[:status]),
        scope: 'dmon_errors.tcp', code: ret[:status]
      )
    end
  end
end

process = CoinMarket::Updater.new(
  coins_num: 20,
  log_level: Logger::INFO,
  log_to_stdout: true
)

loop do
  process.start
  process.sleep_for
end
