require 'sinatra/base'
require_relative 'helpers/configuration'
require_relative 'helpers/browser_logic'
module Inferno
  class App
    class Endpoint < Sinatra::Base
      register Sinatra::ConfigFile

      config_file '../../config.yml'

      helpers Helpers::Configuration
      helpers Helpers::BrowserLogic
      puts root
      set :public_folder, Proc.new { File.join(root, '../../public') }
      set :static, true
      set :views, File.expand_path('../views', __FILE__)
      set(:prefix) { '/' << name[/[^:]+$/].underscore }
    end
  end
end

require_relative 'endpoint/landing'
require_relative 'endpoint/home'