require 'rubygems'
require 'sinatra'
require "sinatra/content_for"
require 'sinatra/streaming'
require 'sinatra/config_file'
require 'json'
require 'omniauth'
require 'omniauth-facebook'
require 'koala'
require 'dalli'
require 'redis'
require 'gexf'
require 'memcachier'
require 'digest/md5'

#--------------Sinatra-Application---------------------------------

config_file 'parameters.yml'

configure do
  set :sessions, true
  set :inline_templates, true
  set :cache, Dalli::Client.new
end

configure :production do
  require 'newrelic_rpm'
end

use OmniAuth::Builder do
  
  facebook_id  = ENV['FACEBOOK_ID'] || settings.facebook_id
  facebook_key = ENV['FACEBOOK_KEY'] || settings.facebook_key
  provider :facebook, facebook_id, facebook_key, :scope => 'user_location,friends_location'
  
  redis_connection_string =  ENV['REDIS_CONNECTION_STRING'] || settings.redis_connection_string
  uri = URI.parse(redis_connection_string)
  REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)

  #for local usage this facebook app returns at http://localhost:4567/
  #provider :facebook, '477713652248633','3cfa969935faf59a6705856bd4ba97ca'
end



get '/' do
  skip_auth
  erb :index
end

get '/home' do
  auth_filter

  erb :graph
end


get '/auth/:provider/callback' do
  @oauth_access_token = request.env['omniauth.auth'][:credentials][:token]

  user = {
      :user_info  => request.env['omniauth.auth'],
  }.to_json

  REDIS.set(request.env['omniauth.auth'][:uid], user)
  session[:uid] = request.env['omniauth.auth'][:uid]
  session[:token] = @oauth_access_token
  session[:authenticated] = true

  redirect to "/home"
end


# construct a friendlist graph and return an gexf file
get '/:provider/friendlist.gexf' do
  auth_filter

  #generating Friendlist graph

  @graph = get_graph_for_user session[:token]
  @friends = get_my_friends session[:uid], @graph

  @my_friends = []
  @me = REDIS.get(session[:uid])

  unless @me.nil?
    @me = JSON.parse @me
  end

  graph = GEXF::Graph.new
  graph.define_node_attribute(:color)
  
  @node_me = graph.create_node label: @me['user_info']['info']['name'], :id => @me['user_info']['uid']
  
  @friends.each do |f|
    visit_friend_tree @node_me, graph, f
  end

  serializer = GEXF::XmlSerializer.new(graph)

  content_type 'text/gexf'
  content = serializer.serialize!
  content = content.sub('<gexf xmlns=\'"http://www.gexf.net/1.2draft\' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi="http://www.gexf.net/1.2draft http://www.gexf.net/1.2draft/gexf.xsd" version="1.2">','<gexf xmlns="http://www.gephi.org/gexf" xmlns:viz="http://www.gephi.org/gexf/viz">')
  content
end


get '/auth/failure' do
  erb "<h1>Authentication Failed</h1>
       <h3>message:<h3>
       <pre>#{params}</pre>"
end

get '/auth/:provider/deauthorized' do
  erb "#{params[:provider]} has deauthorized this app."
end

get '/logout' do
  session[:authenticated] = false
  redirect '/'
end
#------------------------------------------------------------------



#------------node utilities----------------------------------------
def visit_friend_tree me, graph, friend 

  node = graph.nodes[friend['id']]

  if node.nil?
    node = graph.create_node label: friend['name'], :id => friend['id']
    random_color = "%06x" % (rand * 0xffffff)
    friendlist = get_connections friend['id'], @graph
    unless friendlist.nil?
      friendlist.each do |f| 
        node_friend = graph.nodes[f['id']] || graph.create_node(label: f['name'], :id => f['id']) 
        node.connect_to node_friend, :attr => {:color => random_color}
      end  
    end
  end
  node.connect_to me, :attr => {:color => random_color}
  node
end
#------------------------------------------------------------------

#----------------getters with caching------------------------------
def get_connections user_id, graph
  key = Digest::MD5.hexdigest(user_id + @node_me.id.to_s)
  friends = settings.cache.get(key)

  if friends == nil
    friends = @graph.get_connections("me", "mutualfriends/#{user_id}")
    settings.cache.set(key, friends, 3500)
  end

  friends
end

def get_my_friends user_id, graph
  key = Digest::MD5.hexdigest(user_id)
  friends = settings.cache.get(key)

  if friends == nil
    friends = @graph.get_connections("me", "friends")
    settings.cache.set(key, friends, 3500)
  end

  friends
end

def get_graph_for_user token
  graph = settings.cache.get(token)

  if graph == nil
    graph = Koala::Facebook::API.new(token)
    settings.cache.set(token, graph, 3500)
  end

  graph
end

#------------------------------------------------------------------

#---------------filters--------------------------------------------

def auth_filter
  redirect '/' unless (session[:authenticated] && session[:token])
end

def skip_auth
  redirect '/home' if (session[:authenticated] && session[:token])
end

#------------------------------------------------------------------