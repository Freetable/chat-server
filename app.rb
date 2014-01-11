#!/usr/bin/env ruby
# ruby examples/echochat.rb

require 'uuidtools'
require 'mongo_mapper'
require 'ostruct'
require 'json'
require 'base32'
require 'sinatra'
require 'sinatra-websocket'
require 'sinatra/respond_to'
require 'redis'
require 'connection_pool'
require 'hiredis'
require 'em-synchrony'
require 'rest_client'

set :server, 'thin'
set :sockets, []

#Constants (Todo: Move to another file)
OWNERUUID 		= ''
#This isn't a hard limit btw this is used to define socket pools.  
SOCKETS 			= 64
FUNCTIONFAIL 	= '{"result": "-0"}'
RETURNFAIL 		= '{"result": "0"}'
RETURNSUCCESS = '{"result": "1"}'
NETWORKSERVICESURL = 'http://gatekeepers.freetable.info'

#Ban sub doc
class Ban
	include MongoMapper::EmbeddedDocument
	key :uid, String, :required => true
	key :reason, String, :required => true
	key :by, String, :required => true
	key :expires, Time, :require => true
	timestamps!
end

class ServerBans
	include MongoMapper::Document
	many :bans
end

class Users
	include MongoMapper::Document
	key :uid, String, :required => true
	key :sid, String, :required => true
	key :username, String, :required => true
	key :next_song, String
	key :current_room, String
	key :online, Boolean
	timestamps!
end

# This is for the future atm!
class Rooms
	include MongoMapper::Document
	key :name, String, :requried => true										# Room name
	key :owner_uuid, String, :required => true							# Owner uid
	key :description, String, :required => true							# Room Description
	key :last_played, Array																	# Array of songids
	key :mods, Array																				# Array of moderators
	key :current_users, Array																# Array of userids
	many :bans																							# Embedded sublist of bans, the reason we don't do the same with users is there is no need for the data duplication
	timestamps!
end

# This is the server metadata that is spit back when something requests it

class Metadata 
	include MongoMapper::Document
	# Name or short description of server
  key :name, String
	# Long description
  key :description, String
	# URL
  key :url, String
	key :current_users, Integer
	key :max_users, Integer
	key :uuid, String, :required => true
	many :staffs
end

class Staff
	include MongoMapper::Document
	key :uuid, String
	key :acl_level, String
	belongs_to :Metadata
end

# Archive Purposes
# def digest_and_validate( base32 )
#	#This needs to validate the user if authenticated as well.
#
#	payload = OpenStruct.new(JSON.parse(Base32.decode( base32 ),{ :symbolize_names => true }))
#
#  if(payload.from.nil?) then payload.valid = false; payload.error = 'bad from'; 		return payload; end
#  if(payload.to.nil?) 	then payload.valid = false; payload.error = 'bad to';    		return payload; end
#	if(payload.ver.nil?) 	then payload.valid = false; payload.error = 'bad version';	return payload; end
#  if(payload.pay.nil?) 	then payload.valid = false; payload.error = 'bad payload';	return payload; end
#
#	payload.valid = true; payload.error = 'none'; return payload
# end

def validate_user(uid,sid)
	# Check Redis
	@@redis_pool.with do |redis|
		r_result = redis.get(uid)
		return true if ((!r_result.nil?)&&(r_result == sid))
	end
	# Check Network Services
	
	ns_result = OpenStruct.new(JSON.parse(RestClient.get(NETWORKSERVICESURL + '/api/verify_user.pls?wwuserid='+uid+'&sessionid='+sid).to_str))


end

configure do
  if(ENV['OPENSHIFT_MONGODB_DB_URL'].nil?)
    MongoMapper.database = 'ft-chat-server'
		@@redis_pool = ConnectionPool.new(:size => SOCKETS, :timeout => 5) { Redis.new }
  else
		@@redis_pool = ConnectionPool.new(:size => SOCKETS, :timeout => 5) { Redis.new( :host => ENV['OPENSHIFT_REDIS_HOST'], :port => ENV['OPENSHIFT_REDIS_PORT'], :password => ENV['REDIS_PASSWORD'] ) }
		MongoMapper.connection = Mongo::Connection.new(ENV['OPENSHIFT_MONGODB_DB_HOST'],ENV['OPENSHIFT_MONGODB_DB_PORT'])
		MongoMapper.database = ENV['OPENSHIFT_GEAR_NAME']
		# This is kind of mind boggling, but it's the "way"
		MongoMapper.connection[ENV['OPENSHIFT_GEAR_NAME']].authenticate(ENV['OPENSHIFT_MONGODB_DB_USERNAME'],ENV['OPENSHIFT_MONGODB_DB_PASSWORD'])
  end
	# If we have a connection and no meta data, then define this server a uuid
	if !Metadata.all.nil? && Metadata.all.first.nil?
		our_server = Metadata.new
		our_server.uuid = UUIDTools::UUID.random_create
    our_server.save
	end
end

#this should push a static file from somewhere
get '/' do
#Cache for 600 seconds
end

# This is for lb stuff eventually
get '/health' do
#Cache for 60 seconds
'1'
end

get '/api/meta' do
#Cache for 60 seconds
end

get '/api/users' do
#Cache 30 seconds
end

#This should be coming to set the cookies and redirect to /
get '/api/connect/:uid/:sid' do
#No cache
end

post '/api/quit' do
	my_fields = [ 'uid', 'sid' ]

	my_fields.each { |field| if(params[field].nil?); fail = true; break; end }
	return ['-0'=>'-0'].to_json if fail

  my_user = User.find_by_uid(params['uid'])
	
	if(my_user.sid == params['sid'])
		my_user.online = false
	  my_user.save
		return ['1'=>'1'].to_json
	end
	return ['0'=>'0'].to_json 
end

post '/api/heartbeat' do
  my_fields = [ 'uid', 'sid' ]

  my_fields.each { |field| if(params[field].nil?); fail = true; break; end }
  return ['-0'=>'-0'].to_json if fail

	my_user = User.find_by_uid(params['uid'])

	if(my_user.sid == params['sid'])
		my_user.online = true
		my_user.save 
  	return ['1'=>'1'].to_json
	end
	return ['0'=>'0'].to_json	
end

####Per Room

# Index for "room"
get '/:room' do
#Cache for 60 seconds
end

# Send Message to "room"
get '/:room/send_msg/:msg' do
#No Cache
  payload = OpenStruct.new(JSON.parse(Base32.decode( params[:msg] ),{ :symbolize_names => true }))

  if(payload.userid.nil?) then return FUNCTIONFAIL; end
  if(payload.sessionid.nil?) then return FUNCTIONFAIL; end
  if(payload.message.nil?) then return FUNCTIONFAIL; end

	if(validate_user(userid, sessionid))
		# Connect to redis and post
	else
		return RETURNFAIL
	end
	
end


# Websocket for "room"
get '/:room/link' do
#No Cache
  if !request.websocket?
    redirect "/"
  else
		
#		payload = digest_and_validate(params[:payload])

#		return(payload.error) if !payload.valid

    request.websocket do |ws|
		
			redis = Redis.new( :driver => :synchrony, :host => ENV['OPENSHIFT_REDIS_HOST'], :port => ENV['OPENSHIFT_REDIS_PORT'], :password => ENV['REDIS_PASSWORD'] )
  		
			ws.onopen do
        ws.send("Hello World!")
        settings.sockets << ws

      	redis.subscribe(:main) do |on|

        	on.subscribe do |channel, subscriptions|
        		# puts "Subscribed to ##{channel} (#{subscriptions} subscriptions)"
          	ws.send "Subscribed to ##{channel} (#{subscriptions} subscriptions)"
        	end

        	on.message do |channel, message|
          	ws.send "##{channel}: #{message}"
        	end

      	end

      end
      
			ws.onmessage do |msg|
        EM.next_tick { settings.sockets.each{|s| s.send(msg) } }
      end
      
			ws.onclose do
        warn("wetbsocket closed")
        settings.sockets.delete(ws)
      end
    end
  end
end

