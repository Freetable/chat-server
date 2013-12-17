#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'reel'
require 'celluloid/autostart'
require 'celluloid/redis'


class TimeServer
  include Celluloid
  include Celluloid::Notifications

  def initialize
    async.run
  end

  def run
#    now = Time.now.to_f
#    sleep now.ceil - now + 0.001

#    every(1) { publish 'time_change', Time.now }
redis = ::Redis.new(:driver => :celluloid)
begin
  redis.subscribe(:one, :two) do |on|

    on.message do |channel, message|
      puts "##{channel}: #{message}"
      publish "##{channel}", message
    end
  end
rescue ::Redis::BaseConnectionError => error
  puts "#{error}, retrying in 1s"
  sleep 1
  retry
end

  end
end

class TimeClient
  include Celluloid
  include Celluloid::Notifications
  include Celluloid::Logger

  def initialize(websocket)
    info "Streaming time changes to client"
    @socket = websocket
    subscribe('#one', :notify_time_change)
  end

  def notify_time_change(topic, new_time)
    @socket << new_time.inspect
  rescue Reel::SocketError
    info "Time client disconnected"
    terminate
  end
end

class WebServer < Reel::Server
  include Celluloid::Logger

  def initialize(host = "0.0.0.0", port = 1234)
    info "Time server example starting on #{host}:#{port}"
    super(host, port, &method(:on_connection))
  end

    def on_connection(connection)
      while request = connection.request
        case request
        when Reel::Request
          route_request connection, request
        when Reel::WebSocket
          info "Received a WebSocket connection"
          route_websocket request
        end
      end
    end

  def route_request(connection, request)
    #if request.url == "/"
    #  return render_index(connection)
    #end
		
		case request.url
		when '/'
				return render_index(connection)
		when '/query/info'
				return render_info_query(connection)
		else
    #info "404 Not Found: #{request.path}"
    connection.respond :not_found, "Not found"
		end
  end

  def route_websocket(socket)
    if socket.url == "/timeinfo"
      TimeClient.new(socket)
    else
      info "Received invalid WebSocket request for: #{socket.url}"
      socket.close
    end
  end

	def render_info_query(connection)
    info "200 OK: /query/info"
    connection.respond(:ok, { 'Access-Control-Allow-Origin' => '*' }, '{ "name": "blah }')
	end

  def render_index(connection)
    info "200 OK: /"
    connection.respond :ok, <<-HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Reel WebSockets time server example</title>
        <style>
          body {
            font-family: "HelveticaNeue-Light", "Helvetica Neue Light", "Helvetica Neue", Helvetica, Arial, "Lucida Grande", sans-serif;
            font-weight: 300;
            text-align: center;
          }

          #content {
            width: 800px;
            margin: 0 auto;
            background: #EEEEEE;
            padding: 1em;
          }
        </style>
      </head>
      <script>
        var SocketKlass = "MozWebSocket" in window ? MozWebSocket : WebSocket;
        var ws = new SocketKlass('ws://' + window.location.host + '/timeinfo');
        ws.onmessage = function(msg){
          document.getElementById('current-time').innerHTML = msg.data;
        }
      </script>
      <body>
        <div id="content">
          <h1>Time Server Example</h1>
          <div>The time is now: <span id="current-time">...</span></div>
        </div>
      </body>
      </html>
    HTML
  end
end

TimeServer.supervise_as :time_server
WebServer.supervise_as :reel

sleep
