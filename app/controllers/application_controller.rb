class ApplicationController
  attr_reader :request
  attr_reader :logger
  attr_reader :settings
  attr_reader :db

  Time::DATE_FORMATS[:rus_time_date] = '%k:%M %d.%m.%Y'

  def initialize(request, logger, database, settings)
    @request  = request
    @logger   = logger
    @db       = database
    @settings = settings

    @default_layout = 'main'
  end

  def index
    redirect_to '/coins/'
  end

  private

  def params
    request.params
  end

  def url_path_params
    @url_path_params ||= request.params.delete_if { |k, _| [:resource, :action, :id].include?(k) }
  end

  def action_name
    params[:action]
  end

  def db_exec(query_str)
    db.exec query_str
  end

  def url_for(args = {})
    fragments = request.path.split('/').reject(&:empty?)

    if settings[:I18n_enable_url_path_select]
      path_sections, locale = CoinMarket::Router.route_fragments_wo_locale(fragments, true)

      if args[:locale].present?
        if args[:locale].is_a?(Symbol) || args[:locale].is_a?(String)
          path_sections.insert(0, args[:locale])
        elsif args[:locale]
          path_sections.insert(0, I18n.locale)
        end
      end
    else
      path_sections = fragments
    end

    pparams = url_path_params.dup || {}

    if args[:params].present?
      pparams.delete_if { |k, _| args[:params].key?(k.to_sym) }
      pparams.merge!(args[:params])
    end

    '/' + path_sections.join('/') + ( pparams.present? ? ('?' + pparams.to_query) : '' )
  end

  def build_response(body, status: 200)
    [status, { 'Content-Type' => 'text/html' }, [body]]
  end

  def build_response_json(body, status: 200)
    [status, { 'Content-Type' => 'application/json' }, [body.to_json]]
  end

  def redirect_to(uri)
    [302, { 'Location' => uri }, []]
  end

  def layout
    @layout.present? ? @layout : @default_layout
  end

  def file_template(name = action_name, templates_dir = nil, command = 'render', context = self)
    templates_engines_order = %w[slim erb]

    templates_dir = self.class.name.downcase.sub('controller', '') if templates_dir.blank?
    templates_engines_order.each do |engine_ext|
      res = render_engine_template(engine_ext, command, templates_dir, name, context)
      return res unless res.nil?
    end

    strOut = "ERROR: no available template file or engine for action \"#{name}\""
    logger.debug(strOut + " in \"#{templates_dir}\"")
    strOut
  end

  def template_file_path_for(file_name)
    File.expand_path(File.join('../../views', file_name), __FILE__)
  end

  def render(template_file = action_name, render_layout = true)
    return render_with_layout if render_layout && layout.present?
    render_template(template_file)
  end

  def render_with_layout(template_file = action_name, context = self)
    layout_template  = file_template(layout, 'layouts', 'fetch', context)
    content_template = file_template(template_file, nil, 'render', context).html_safe

    layout_template.render(context) { content_template }
  end

  def render_template(template_file = action_name, context = self)
    file_template(template_file, nil, 'render', context)
  end

  def render_engine_template(engine_ext, cmd, templates_dir, name, context)
    template_file = File.join(templates_dir, "#{name}.html.#{engine_ext}")
    file_path = template_file_path_for(template_file)

    if File.exist?(file_path)
      method_name = "#{cmd}_file_#{engine_ext}"
      return send(method_name, file_path, context) if respond_to?(method_name, true)
    end
    nil
  end

  ## -- Template Rendering Engines -- #

  # ERB Rendering

  def fetch_file_erb(file_path, context = self)
    raw = File.read(file_path)
    ERB.new(raw).result(context.send('binding'))
  end

  def render_file_erb(file_path, context = self)
    fetch_file_erb(file_path, context)
  end

  # SLIM Rendering

  def fetch_file_slim(file_path, _context)
    Slim::Template.new(file_path)
  end

  def render_file_slim(file_path, context = self)
    Slim::Template.new(file_path).render(context)
  end
end
