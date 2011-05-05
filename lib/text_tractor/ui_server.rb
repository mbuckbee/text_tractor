require 'haml'
require 'sass'
require 'digest/md5'

module TextTractor
  class UiServer < TextTractor::Base
    helpers do 
      def current_user
        Users.get(env["REMOTE_USER"])
      end

      def pjax?
        env.key? "HTTP_X_PJAX" || params["layout"] == "false"
      end

      def projects
        Projects.for_user(current_user).sort { |a, b| b.name <=> a.name }
      end
    end
    
    use Rack::Auth::Basic do |username, password|
      unless Users.exists?(TextTractor.configuration.default_username)
        Users.create(username: TextTractor.configuration.default_username, password: TextTractor.configuration.default_password, name: "Default User", superuser: true) 
      end

      Users.authenticate(username, password)
    end
    
    set :environment, TextTractor.configuration.environment
    
    set :public, File.expand_path("../../../assets", __FILE__)
    set :views, File.expand_path("../../../views", __FILE__)
    
    def initialize(app=nil)
      super
    end
    
    def render_haml(template)
      haml template, :layout => !pjax? 
    end

    get '/' do
      @projects = Projects.for_user(current_user)
      render_haml :index
    end

    get '/styles.css' do
      scss :styles
    end

    get '/users' do
      return not_authorised unless current_user["superuser"]
      
      @users = Users.all
      render_haml :users
    end

    post '/users' do
      return not_authorised unless current_user["superuser"]
      
      Users.create(params[:user])  
      redirect "/users"
    end

    get '/projects/new' do
      return not_authorised unless current_user["superuser"]
      
      @users = Users.all
      render_haml :"projects/new"
    end
    
    get '/projects/:api_key/:locale/*' do |api_key, locale, path|
      @api_key = api_key
      @locale = locale
      @path = path
      @key = path.gsub("/", ".")
      encoded = JSON.parse(redis.get("projects:#{@api_key}:draft_blurbs:#{@key}"))
      @blurb = encoded[locale] || ""

      render_haml :"blurbs/edit"
    end
    
    post '/projects/:api_key/:locale/*' do |api_key, locale, path|
      @api_key = api_key
      @locale = locale
      @project = Projects.get(api_key)
      @phrase_key = path.gsub("/", ".")
      @key = "#{locale}.#{@phrase_key}"
      @value = params[:blurb]
      
      @project.update_draft_blurbs({ @key => @value }, { :overwrite => true })
      @phrase = JSON.parse(redis.get("projects:#{@api_key}:draft_blurbs:#{@phrase_key}"))
      
      if pjax?
        @value = haml :"blurbs/value", :layout => false, :locals => { 
          phrase: @phrase, 
          key: @key, 
          locale: @locale, 
          original: @phrase[@project.default_locale], 
          show_original: @project.default_locale != @locale 
        }
        
        haml :"blurbs/_blurb", :layout => false
      else
        redirect "/projects/#{api_key}"
      end
    end
    
    def phrase_list(api_key, locale = nil)
      return not_authorised unless Projects.authorised?(current_user, api_key)
      
      @project = Projects.get(api_key)
      @locale = locale || @project.default_locale
      @phrases = @project.draft_phrases
      
      if @phrases.size > 0
        render_haml :"projects/show"
      else
        render_haml :"projects/getting_started"
      end
    end
    
    get '/projects/:api_key' do |api_key|
      return phrase_list(api_key)
    end
    
    get '/projects/:api_key/:locale' do |api_key, locale|
      return phrase_list(api_key, locale)
    end
    
    post '/projects' do
      project = Projects.create(params[:project])
      redirect "/projects/#{project["api_key"]}"
    end
  end
end
