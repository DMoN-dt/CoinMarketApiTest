require_relative 'coins_web_router'
require 'rack'

module CoinMarket
  class Web
    attr_reader :settings
    attr_reader :db
    attr_reader :logger
    attr_reader :price_additional_currency

    # General initializations
    def initialize(iparams = {})
      @settings = General.settings
      default_params_if_not_specified(iparams)
      set_additional_currency(iparams)

      @logger = General.open_log(iparams[:log_level], iparams[:log_file_path], iparams[:log_to_stdout])

      initialize_i18n
      initialize_database!
    end

    def call(env)
      request = Rack::Request.new(env)
      serve_request(request)
    end

    private

    def default_params_if_not_specified(iparams)
      default_params = {
        price_additional_currency: @settings[:price_additional_currency],
        log_level: Logger::ERROR,
        log_to_stdout: true,
        log_file_path: @settings[:web_log_file_path]
      }
      default_params.each_key { |key| iparams[key] = default_params[key] unless iparams.key?(key) }
    end

    def set_additional_currency(iparams)
      @price_additional_currency = iparams[:price_additional_currency]
      @settings[:price_additional_currency] = @price_additional_currency
    end

    def initialize_i18n
      I18n.load_path = @settings[:I18n_load_path]
      I18n.available_locales = @settings[:I18n_available_locales]
      I18n.default_locale = @settings[:I18n_default_locale]
      I18n.backend.load_translations
    end

    def initialize_database!
      @db = DbHelper.new(logger)
    end

    def serve_request(request)
      Router.new(request, logger, db, settings).route!
    end
  end
end
