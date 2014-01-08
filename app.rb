#!/usr/bin/env ruby
# ruby examples/echochat.rb

require 'ostruct'
require 'json'
require 'base32'
require 'sinatra'
require 'sinatra-websocket'
require 'sinatra/respond_to'
require 'redis'

set :server, 'thin'
set :sockets, []

def digest_and_validate( base32 )
	#This needs to validate the user if authenticated as well.

	payload = OpenStruct.new(JSON.parse(Base32.decode( base32 ),{ :symbolize_names => true }))

  if(payload.from.nil?) then payload.valid = false; payload.error = 'bad from'; 		return payload; end
  if(payload.to.nil?) 	then payload.valid = false; payload.error = 'bad to';    		return payload; end
	if(payload.ver.nil?) 	then payload.valid = false; payload.error = 'bad version';	return payload; end
  if(payload.pay.nil?) 	then payload.valid = false; payload.error = 'bad payload';	return payload; end

	payload.valid = true; payload.error = 'none'; return payload

end

get '/health' do
'1'
end

get '/api/publish/:payload' do

end

get '/' do
  if !request.websocket?
    #redirect "/"
  else
		
#		payload = digest_and_validate(params[:payload])

#		return(payload.error) if !payload.valid

    request.websocket do |ws|
		
			redis = Redis.new( :host => ENV['OPENSHIFT_REDIS_HOST'], :port => ENV['OPENSHIFT_REDIS_PORT'], :password => ENV['REDIS_PASSWORD'] )
  		
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

