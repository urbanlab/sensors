=begin
- multiplexer : {"description" => "bla", "supported" => ["ain", "din"]}
Sur network:<network>:multiplexers = hash(multipl-id, objet multiplexer)

- sensor : {"description" => "verbose", "function" => "din", "period" => 1000, "unit" => "°C", "rpn" => "X 7 *"}
Sur network:<network>:multiplexers:<multipl-id>:sensors = hash (pin, objet sensor)

- actuator : {"pin" => 13, "fonction" => "bli"}
Sur network:<network>:multiplexers:<multipl-id>:actuators = hash (pin, objet actuator)

=end
require 'rubygems'
require 'redis/connection/hiredis'
require 'redis'

PREFIX = "network"
MULTI  = "multiplexers"
SENS   = "sensors"
ACTU   = "actuators"
VALUE  = "value"
CONF   = "config"

class Redis_interface
	
	def initialize(host, port, network)
		@redis = Redis.new :host => host, :port => port
		@network = network
		@prefix = "#{PREFIX}:#{@network}"
	end
	
	def get_multi_keys
		@redis.hkeys("#{@prefix}:#{MULTI}:#{CONF}").collect{|k| k.to_i}
	end
	
	def get_multi_config multi_id
		JSON.parse(@redis.hget("#{@prefix}:#{MULTI}:#{CONF}", multi_id))
	end
	
	def set_multi_config multi_id, config
		path = "#{@prefix}:#{MULTI}"
		@redis.hset("#{path}:#{CONF}", multi_id, config.to_json)
		@redis.publish("#{path}:#{multi_id}:#{CONF}", config.to_json)
	end
	
	def knows_multi? multi_id
		path = "#{@prefix}:#{MULTI}:#{CONF}"
		@redis.hexists(path, multi_id)
	end
	
	def publish_value(multi_id, sensor, value)
		path = "#{@prefix}:#{MULTI}:#{multi_id}:#{SENS}"
		key = {"value" => value,"timestamp" => Time.now.to_i}.to_json
		@redis.hset("#{path}:#{VALUE}", sensor, key)
		@redis.publish("#{path}:#{sensor}:#{VALUE}", key)
	end
	
	def set_sensor_config multi_id, pin, config
		path = "#{@prefix}:#{MULTI}:#{multi_id}:#{SENS}"
		@redis.hset("#{path}:#{CONF}", pin, config.to_json)
		@redis.publish("#{path}:#{pin}:#{CONF}", config.to_json)
	end

	def on_new_sensor(&block)
		Thread.new{
			redis = Redis.new
			redis.psubscribe("#{@prefix}:#{MULTI}:*:#{SENS}:*:#{CONF}") do |on|
				on.pmessage do |pattern, channel, message|
					parse = Hash[ *channel.split(":")[0..-2] ]
					yield parse[MULTI], parse[SENS], JSON.parse(message)
				end
			end
		}
	end
end
