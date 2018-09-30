require_relative 'coins_general'

require 'erb'
require 'slim'

[
  '../../app/models/*.rb',
  '../../app/controllers/*.rb',
].each do |required_path|
  Dir.glob(File.expand_path(required_path, __FILE__)).each { |file| require(file) }
end

module CoinMarket
  class Router
    attr_reader :logger
    attr_reader :db
    attr_reader :url_contains_i18n

    class << self
      def controller_name(name)
        "#{name.capitalize}Controller"
      end

      def controller_class(cname)
        Object.const_get(cname)
      rescue NameError
        nil
      end

      def route_fragments_wo_locale(fragments, url_contains_i18n)
        if !fragments[0].nil? && url_contains_i18n
          locale = I18n.available_locales.select { |x| x.to_s == fragments[0] }.first

          # If Locale not found then maybe it is a controller name
          fragments.shift(1) if locale.present? || controller_class(controller_name(fragments[0])).nil?
        end

        [fragments, locale]
      end
    end

    def initialize(request, logger, database, settings)
      @request  = request
      @logger   = logger
      @db       = database
      @settings = settings
      @url_contains_i18n = settings[:I18n_enable_url_path_select]

      $tablename_coins = settings[:tablename_coins]
      $tablename_coins_history = settings[:tablename_coins_history]

      logger.debug "New request path: #{@request.path}, params: #{@request.params.to_json}"
    end

    def route!
      if (klass = Router.controller_class(controller_name))
        add_route_info_to_request_params!

        controller = klass.new(@request, logger, @db, @settings)
        action = route_info[:action]

        if controller.respond_to?(action)
          logger.debug "Routing to #{klass}##{action}"
          return controller.public_send(action)
        end
      end

      not_found
    end

    private

    def not_found(msg = 'Not Found')
      [404, { 'Content-Type' => 'text/plain' }, [msg]]
    end

    def route_info
      @route_info ||= begin
        # Verify whether URL should start with Locale ID and is contains it
        path_sections, locale = Router.route_fragments_wo_locale(path_fragments.dup, url_contains_i18n)

        I18n.locale = (locale || I18n.default_locale)

        resource = (path_sections[0] || 'application')
        id, action = find_id_and_action(path_sections[1])

        { resource: resource, action: action, id: id }
      end
    end

    def add_route_info_to_request_params!
      @request.params.merge!(route_info)
    end

    def find_id_and_action(fragment)
      case fragment
      when 'new'
        [nil, :new]
      when 'edit'
        [nil, :edit]
      when nil
        action = (@request.get? ? :index : :create)
        [nil, action]
      else
        if @request.get?
          action = :show
        elsif @request.delete?
          action = :destroy
        elsif @request.put? || @request.patch?
          action = :update
        else
          action = :show
        end
        [fragment, action]
      end
    end

    def path_fragments
      @path_fragments ||= @request.path.split('/').reject(&:empty?)
    end

    def controller_name(name = route_info[:resource])
      "#{name.capitalize}Controller"
    end
  end
end
