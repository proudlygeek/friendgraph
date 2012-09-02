require 'rubygems'
require 'sinatra'
require "sinatra/content_for"
require 'sinatra/streaming'
require 'json'
require 'omniauth'
require 'omniauth-facebook'
require 'koala'
require 'dalli'
require 'redis'
require 'open-uri'
require 'gexf'


configure do
  set :sessions, true
  set :inline_templates, true
  set :cache, Dalli::Client.new
  uri = URI.parse('redis://toretto460:e2a5774a30709ac1448d8a7e39434ecf@barb.redistogo.com:9392/')
  REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end

use OmniAuth::Builder do
  provider :facebook, '276684505778296','5c800d3d9c1c1e709d7195da93e7dce7', :scope => 'user_location,friends_location'
  #for local usage this facebook app return at http://localhost:4567/
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

get '/:provider/friendlist.gexf' do
  auth_filter

  #generating Friendslist graph

  @graph = get_graph_for_user session[:token]
  @friends = get_my_friends session[:uid], @graph

  @my_friends = []
  @me = REDIS.get(session[:uid])

  unless @me.nil?
    @me = JSON.parse @me
  end

  graph = GEXF::Graph.new
  graph.define_node_attribute(:color)
  
  node_me = graph.create_node label: @me['user_info']['info']['name'], :id => @me['user_info']['uid'], :color => 'red'
  
  @friends.each do |f|
    friend = graph.create_node label: f['name'], :id => f['id']  
  end

  @friends.each do |f|

    node_me.connect_to graph.nodes[f['id']]  

    friends_of_my_friend = get_friendlist_for_user(f['id'], @graph)

    friends_of_my_friend.each do |fomf|
      graph.nodes[f['id']].connect_to graph.nodes[fomf['id']]
    end
    
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

def get_friendlist_for_user user_id, graph
  friends = settings.cache.get(user_id)

  if friends == nil
    friends = @graph.get_connections("me", "mutualfriends/#{user_id}")
    settings.cache.set(user_id, friends, 3500)
  end

  friends
end

def get_my_friends user_id, graph
  friends = settings.cache.get(user_id)

  if friends == nil
    friends = @graph.get_connections("me", "friends")
    settings.cache.set(user_id, friends, 3500)
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

def auth_filter
  redirect '/' unless (session[:authenticated] && session[:token])
end

def skip_auth
  redirect '/home' if (session[:authenticated] && session[:token])
end