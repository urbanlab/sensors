=begin
- multiplexer : {"description" => "bla", "supported" => ["ain", "din"]}
Sur network:<network>:multiplexers = hash(multipl-id, objet multiplexer)

- sensor : {"description" => "verbose", "function" => "din", "period" => 1000, "unit" => "°C", "rpn" => "X 7 *"}
Sur network:<network>:multiplexers:<multipl-id>:sensors = hash (pin, objet sensor)

- actuator : {"pin" => 13, "fonction" => "bli"}
Sur network:<network>:multiplexers:<multipl-id>:actuators = hash (pin, objet actuator)

=end
require 'rubygems'
require 'json'
require 'redis/connection/hiredis'
require 'redis'

PREFIX = "network"
MULTI  = "multiplexer"
SENS   = "sensor"
ACTU   = "actuator"
VALUE  = "value"
CONF   = "config"
DEL    = "delete"
PROF   = "profile"

class Redis_interface
	
	def initialize(network, host = 'localhost', port = 6379)
		@host = host
		@port = port
		@redis = Redis.new :host => host, :port => port
		@network = network
		@prefix = "#{PREFIX}:#{@network}"
	end
	
	##### Multiplexer management #####
	
	# List all the registered multiplexers key in an array.
	#
	def get_multi_keys
		@redis.hkeys("#{@prefix}.#{MULTI}.#{CONF}").collect{|k| k.to_i}
	end
	
	# With integer id as parameter : get the multiplexer config
	# Without parameter : get all the multiplexers config in a hash {id => config}
	#
	def get_multi_config(multi_id = nil)
		if multi_id
			JSON.parse(@redis.hget("#{@prefix}.#{MULTI}.#{CONF}", multi_id))
		else
			Hash[*configs.collect{|id, conf| [id.to_i, JSON.parse(conf)]}.flatten]
		end
	end
	
	# Assign a config to a multiplexer TODO : verify if the multi exist
	#
	def set_multi_config multi_id, config
		path = "#{@prefix}.#{MULTI}"
		@redis.hset("#{path}.#{CONF}", multi_id, config.to_json)
		@redis.publish("#{path}:#{multi_id}.#{CONF}", config.to_json)
	end
	
	# Return true if a multi is registered
	#
	def knows_multi? multi_id
		path = "#{@prefix}.#{MULTI}.#{CONF}"
		@redis.hexists(path, multi_id)
	end
	
	##### Sensor management #####
	
	# Configure a sensor. TODO verify if the multi exist, adapt to profile system
	# return true if this was a new sensor
	#
	def set_sensor_config multi_id, pin, config
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}"
		@redis.publish("#{path}:#{pin}.#{CONF}", config.to_json)
		@redis.hset("#{path}.#{CONF}", pin, config.to_json)
	end
	
	# Unregister a sensor. TODO separate client side (publish) and demon side (hdel)
	#
	def remove_sensor multi_id, pin
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}"
		@redis.publish("#{path}:#{pin}.#{DEL}", pin)
		@redis.hdel("#{path}.#{CONF}", pin)
	end
	
	# Get all sensors config of a multi, in form {pin => config}
	#
	def get_sensors_config multi_id
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}.#{CONF}"
		ans = {}
		@redis.hgetall(path).each do |k, v| # TODO ugly
			ans[k.to_i] = JSON.parse(v)
		end
		ans
	end

	##### Profile utilitie #####
	
	# Register a sensor/actuator profile
	#
	def add_profile(name, profile)
		@redis.hset("#{CONF}.#{PROF}", name, profile.to_json)
	end
	
	# List the profiles' names
	#
	def list_profile
		@redis.hkeys("#{CONF}.#{PROF}")
	end
	
	# With string parameter : get a profile
	# Without : get all profile in a hash {name => profile}
	#
	def get_profile(profile = nil)
		profile ? @redis.hget("#{CONF}.#{PROF}", profile) : @redis.hgetall("#{CONF}.#{PROF}")
	end
	
	##### Actuator management #####
	# TODO almost everything
	
	# Define an actuator's state
	# TODO rewrite, implement in demon and firmware...
	#
	def set_actuator_value(multi_id, actuator, value)
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{ACTU}"
		key = {"value" => value,"timestamp" => Time.now.to_f}.to_json
		@redis.hset("#{path}.#{VALUE}", actuator, key)
		@redis.publish("#{path}:#{actuator}.#{VALUE}", value)
	end
	
	##### Callbacks #####
	
	# Callback when a value is published on redis.
	# Type might be :sensor or :actuator
	# block has 3 arguments : multiplexer's id, sensor's pin, value
	#
	def on_published_value(type, multi = "*", pin = "*", &block)
		Thread.new{
			type = {:sensor => SENS, :actuator => ACTU}[type]
			redis = Redis.new
			redis.psubscribe("#{@prefix}.#{MULTI}:#{multi}.#{type}:#{pin}.value") do |on|
				on.pmessage do |pattern, channel, valeur|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ]
					yield parse[MULTI], parse[SENS], valeur
				end
			end
		}
	end

	
	##### Demon's utilities #####
	
	# Publish a sensor's value TODO verify if the sensor and the multi are registered
	#
	def publish_value(multi_id, sensor, value)
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}"
		key = {"value" => value,"timestamp" => Time.now.to_f}.to_json
		@redis.hset("#{path}.#{VALUE}", sensor, key)
		@redis.publish("#{path}:#{sensor}.#{VALUE}", value)
	end
	
		
	# Callback when a client request to add a sensor
	# block has 3 arguments : multiplexer's id, sensor's pin and sensor's config
	#
	def on_new_sensor(&block)
		Thread.new{
			redis = Redis.new :host => @host, :port => @port
			redis.psubscribe("#{@prefix}.#{MULTI}:*.#{SENS}:*.#{CONF}") do |on|
				on.pmessage do |pattern, channel, message|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ]
					yield parse[MULTI], parse[SENS], JSON.parse(message)
				end
			end
		}
	end
	
	# Callback when a client request to delete a sensor
	# block has 2 arguments : multiplexer's id, sensor's pin
	#
	def on_deleted_sensor(&block)
		Thread.new{
			redis = Redis.new :host => @host, :port => @port
			redis.psubscribe("#{@prefix}.#{MULTI}:*.#{SENS}:*.#{DEL}") do |on|
				on.pmessage do |pattern, channel, message|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ]
					yield parse[MULTI], parse[SENS]
				end
			end
		}
	end
end

