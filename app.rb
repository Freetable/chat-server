set :server, 'thin'
set :sockets, []

#Constants (Todo: Move to another file)
OWNERUUID 		      = ''
#This isn't a hard limit btw this is used to define socket pools.  
MAXUSERS            = 64
SOCKETS             = 64
NETWORKSERVICESURL  = 'http://gatekeepers.freetable.info'
TIMETOLIVE          = 600

class String
  def to_roomtitle
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1 \2').
    gsub(/([a-z\d])([A-Z])/,'\1 \2').
    tr("-", " ").
    downcase.capitalize
  end
end

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
	key :username, String, :required => true
	key :next_song, String
	key :current_room, String
	key :online, Boolean
	timestamps!
end

# This is for the future atm!
class Rooms
	include MongoMapper::Document
	key :name, String, :requried => true								# Room name
	key :owner_uuid, String, :required => true							# Owner uid
	key :description, String, :required => true							# Room Description
	key :last_played, Array												# Array of songids
	key :mods, Array													# Array of moderators
	key :current_users, Array											# Array of userids
	many :bans															# Embedded sublist of bans, the reason we don't do the same with users is there is no need for the data duplication
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

class WebsocketFunctions
  # payload, redis, websocket

  def initialize(uid, redis, ws)
    @uid = uid
    @redis = redis
    @ws = ws
  end


  def f111(p)
    # Server To Client
    # Message
    # Payload includes from, to, level, data
    # From will be the chat servers uuid if it's from the server
    # To will either be the uuid of the person it's directly to
    # Or 0 for everyone

  end

  def f112(p)
    # Server To Client
    # Alert
    # Payload includes from, level, data
    # From will be the chat servers uuid if it's from the server

  end

  def f121(p)
    # Server To Client
    # Userlist
    # use a function to return a user list to cut down on code dup with function 621
    # Payload is an array of hashs [{:name => '', :uid => '', :level => ''},{:name => '', :uid => '', :level => ''}]
  end

  def f122(p)
    # Server To Client
    # Useradd
    # Payload includes: name, uid, level
  end

  def f123(p)
    # Server To Client
    # Userdel
    # Payload includes: uid
  end

  def f131(p)
    # Server To Client
    # Queuelist
    # Payload is an array of hashs [:uid,:uid,:uid,:uid,:uid]
  end

  def f132(p)
    # Server To Client
    # Queueadd
    # Payload includes: uid
  end

  def f133(p)
    # Server To Client
    # Queuedel
    # Payload includes: uid
  end

  def f134(p)
    # Server To Client
    # Queuepos
    # Payload includes: index
  end

  def f141(p)
    # Server To Client
    # Nextsong
    # Payload includes: uid, skip
  end

  def f142(p)
    # Server To Client
    # Noop
    # Payload is blank
  end

  def f143(p)
    # Server To Client
    # Ping?
    # Payload is blank
  end

  def f611(p)
    # Client To Server
    # Message
    # Payload includes: to, data, level
    # to is either uid of receiver or 0 for everyone
    # Use Redis bus
  end

  def f612(p)
    # Client To Server
    # Message
    # Payload includes: to, data, level
    # to is either uid of receiver or 0 for everyone
    # Use Redis bus
  end

  def f621(p)
    # Client To Server
    # Userlist
    # Use the redis bus to trigger a server to client userlist
  end

  def f631(p)
    # Client To Server
    # Useradd
    # See if there is an avaiable spot
    # Add us
    # Use the redis bus to trigger a server to client useradd 
  end

  def f632(p)
    # Client To Server
    # Userdel
    # See if we are up there
    # Remove us
    # Use the redis bus to trigger a server to client userdel
  end

  def f641(p)
    # Client To Server
    # Skip
    # If it's our song playing then skip it right meow
    # If it's not our song, then increment the tally to skip
    # If enough tallyed then force skip song using redis bus
  end

  def f642(p)
    # Client To Server
    # Noop
  end

  def f643(p)
    # Client To Server
    # Pong
  end

  def f644(p)
    # Client To Server
    # Part
  end
end

def get_current_users_count
  Users.find_by_online(true).all.count
end

def get_current_users
  Users.find_by_online(true).all
end

def get_max_users
  MAXUSERS
end

def get_metadata
  Metadata.all.first
end

def get_hostname
  Metadata.all.first.name
end

def get_uid
  cookies[:WWUSERID]
end

def get_sid
  cookies[:sessionid]
end

def get_username
  Users.find_by_uid(get_uid).username
end

def validate_user_with_cookies
  validate_user(cookies[:WWUSERID], cookies[:sessionid])
end

# Build Function  -- Simplify logic down below
def bf(fn, data)
  { :function => fn, :payload => data}.to_json
end

def process_function(args)
  ftmsg = args[:ftmsg]
  uid = args[:uid]
  redis = args[:redis]
  ws = args[:ws]
  
  return false if ftmsg.function.nil?
  return false if ftmsg.payload.nil?

  wsf = WebsocketFunctions.new(uid, redis, ws)
  
  logger.info('wsf started')

  wsf.send('f'+ftmsg.function, ftmsg.payload) if wsf.respond_to?('f'+ftmsg.function)
  return true if wsf.respond_to?(ftmsg.function)
  return false
end

def validate_user(uid,sid)

  # Check Redis

  @@redis_pool.with do |redis|
    r_result = redis.get(uid)
    # If result is not nil and the result of the key uid is sid
    if ((!r_result.nil?)&&(r_result == sid))
      # If Redis has the user, the user should have already been created
      redis.expire(uid,TIMETOLIVE)
      user = Users.find_by_uid(uid)
      user.online = true
      user.save
      return true
    end
  end

  # If the person isn't in Redis, does Network Services know about ya?

  ns_result = OpenStruct.new(JSON.parse(RestClient.get(NETWORKSERVICESURL + '/api/verify_user.pls?wwuserid='+uid+'&sessionid='+sid).to_str).first).result.to_i
  logger.info("validate_user(#{uid}, #{sid}) network services result: #{ns_result}")
  if (ns_result == 1)
    user = Users.find_by_uid(uid) || Users.new
    user.uid = uid
    username = OpenStruct.new(JSON.parse(RestClient.get(NETWORKSERVICESURL + '/api/query_user.pls?wwuserid='+uid).to_str).first).result
    logger.info('validate_user.username: '+ username)
    user.username = username
    user.online = true
    user.save
    #Update Redis
    @@redis_pool.with do |redis|
      redis.set(uid,sid)
      redis.expire(uid,TIMETOLIVE)
    end
  else
    return false
  end
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


# This is for lb stuff eventually
get '/health' do
#Cache for 60 seconds
'1'
end

get '/api/meta' do
#Cache for 60 seconds
end

#This should be coming to set the cookies and redirect to /
get '/api/connect/:uid/:sid' do
  #No cache
  #"High aswell #{params[:uid]} @ #{params[:sid]}"
  answer = validate_user(params[:uid], params[:sid])
  if answer
    cookies[:WWUSERID] = params[:uid]
    cookies[:sessionid] = params[:sid]
    return Freetable::RETURNSUCCESS
  else
    return Freetable::RETURNFAIL
  end
end

####Per Room

# Index for "room"
get '/:room' do
  #Cache for 60 seconds
  redirect './' if !validate_user_with_cookies
  erb :room, :locals => {:get_room => params[:room], :get_room_name => params[:room].to_roomtitle }
end

# Websocket for "room"
get '/:room/link' do
#No Cache
  get_room = params[:room]
  redirect './' if !validate_user_with_cookies || !request.websocket?
  
  request.websocket do |ws|
    
    redis = Redis.new( :driver => :synchrony, :host => ENV['OPENSHIFT_REDIS_HOST'], :port => ENV['OPENSHIFT_REDIS_PORT'], :password => ENV['REDIS_PASSWORD'], :timeout => 0)
		
		ws.onopen do
      ws.send(bf(142,''))
      settings.sockets << ws
    	redis.subscribe(get_room) do |on|

      	on.subscribe do |channel, subscriptions|
      		# puts "Subscribed to ##{channel} (#{subscriptions} subscriptions)"
          # Send a user joined message to the room
          redis.publish(get_room, bf(122,{:name => get_username, :uuid => get_uid}))
      	end

      	on.message do |channel, message|
          # Server To Client
          process_function(:ftmsg => OpenStruct.new(JSON.parse(message)), :uid => get_uid, :redis => redis, :ws => ws)
      	end
    	end
    end
        
		ws.onclose do
      warn("websocket closed")
      settings.sockets.delete(ws)
    end

    ws.onmessage do |message|
      #Client To Server
      process_function(:ftmsg => OpenStruct.new(JSON.parse(message)), :uid => get_uid, :redis => redis, :ws => ws)
    end
  end
end


#this should push a static file from somewhere
get '/' do
#Cache for 600 seconds
  redirect NETWORKSERVICESURL
end

