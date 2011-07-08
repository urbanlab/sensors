=begin
- Multiplexer's config mean : {"description" => "descriptive goes here", "supported" => ["profile1", "profile2"]}
- Sensor's config mean : {"description" => "descriptive", "profile" => "profile_name", "period" => 1000 (ms)}
- Actuator's config mean : TODO
- Profile mean : { "function" => "firmware function", "description" => "Get temperature !", "rpn" => "2 X *", "unit" => "Celsius"}
=end
require 'rubygems'
require 'json'
require 'redis/connection/hiredis'
require 'redis'


class Redis_interface
	
	PREFIX = "network"
	MULTI  = "multiplexer"
	SENS   = "sensor"
	ACTU   = "actuator"
	VALUE  = "value"
	CONF   = "config"
	DEL    = "delete"
	PROF   = "profile"
	
	def initialize(network, host = 'localhost', port = 6379)
		@host = host
		@port = port
		@redis = Redis.new :host => host, :port => port
		@network = network
		@prefix = "#{PREFIX}:#{@network}"
	end
	
	##### Multiplexer management #####
	

	# get all the multiplexers config in a hash {id => config}
	#
	def list_multis
		configs = @redis.hgetall("#{@prefix}.#{MULTI}.#{CONF}")
		return Hash[*configs.collect{|id, conf| [id.to_i, JSON.parse(conf)]}.flatten]
	end
	
	# get the multiplexer config or nil if does no exist
	#
	def get_multi_config( multi_id )
		return nil unless knows_multi? multi_id
		JSON.parse(@redis.hget("#{@prefix}.#{MULTI}.#{CONF}", multi_id)) if knows_multi? multi_id
	end
	
	# Register description of a multiplexer. Return false if the multi doesn't exist
	#
	def set_description multi_id, description
		if knows_multi? multi_id
			path = "#{@prefix}.#{MULTI}"
			config = JSON.parse(@redis.hget("#{path}.#{CONF}", multi_id))
			config["description"] = description
			@redis.hset("#{path}.#{CONF}", multi_id, config.to_json)
			@redis.publish("#{path}:#{multi_id}.#{CONF}", config.to_json)
			return true
		else
			return false
		end
	end
	
	# Return true if a multi is registered
	#
	def knows_multi? multi_id
		path = "#{@prefix}.#{MULTI}.#{CONF}"
		@redis.hexists(path, multi_id)
	end
	
	##### Sensor management #####
	
	# Return true if the sensor exist.
	#
	def knows_sensor? multi_id, pin
		(knows_multi? multi_id) && @redis.hexists("#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}.#{CONF}", pin)
	end
	
	# Get a sensor's config
	#
	def get_sensor_config multi_id, pin
		return nil unless knows_sensor? multi_id, pin
		JSON.parse(@redis.hget("#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}.#{CONF}", pin))
	end
	
	# Register a sensor.
	# return true if this was a success
	#
	def add_sensor multi_id, pin, config
		return false unless (knows_multi? multi_id) && (knows_profile? config[PROF])
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}"
		@redis.publish("#{path}:#{pin}.#{CONF}", config.to_json)
		@redis.hset("#{path}.#{CONF}", pin, config.to_json)
		return true
	end
	
	# Unregister a sensor. Return true if something was removed
	# TODO does not publish if no multi ?
	def remove_sensor multi_id, pin
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}"
		@redis.publish("#{path}:#{pin}.#{DEL}", pin)
		@redis.hdel("#{path}.#{CONF}", pin) == 1
	end
	
	# Get all sensors config of a multi, in form {pin => config}
	# Return {} if there were no sensor, return nil if the multi does not exists
	#
	def list_sensors multi_id
		return nil unless knows_multi? multi_id
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}.#{CONF}"
		Hash[*@redis.hgetall(path).collect {|id, config| [id.to_i, JSON.parse(config)]}.flatten]
	end

	##### Profile utilitie #####
	
	# Return true if the profile exist
	#
	def knows_profile? name
		@redis.hexists("#{CONF}.#{PROF}", name)
	end
	
	# Register a sensor/actuator profile
	#
	def add_profile(name, profile)
		@redis.hset("#{CONF}.#{PROF}", name, profile.to_json)
	end
	
	# Unregister a profile TODO : check if users ?
	#
	
	
	# get all profile in a hash {name => profile}
	#
	def list_profiles
		Hash[*@redis.hgetall("#{CONF}.#{PROF}").collect{|name, profile| [name, JSON.parse(profile)]}.flatten]
	end
	
	# With string parameter : get a profile
	#
	def get_profile(profile)
		return nil unless knows_profile? profile
		JSON.parse(@redis.hget("#{CONF}.#{PROF}", profile))
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
					yield parse[MULTI].to_i, parse[SENS].to_i, valeur.to_f
				end
			end
		}
	end

	
	##### Demon's utilities #####
	
	def flushdb
		@redis.flushdb
	end

	# Assign a config to a multiplexer
	#
	def set_multi_config multi_id, config
		path = "#{@prefix}.#{MULTI}"
		@redis.hset("#{path}.#{CONF}", multi_id, config.to_json)
		@redis.publish("#{path}:#{multi_id}.#{CONF}", config.to_json)
	end
	
	# Publish a sensor's value
	#
	def publish_value(multi_id, sensor, value)
		return false unless knows_sensor? multi_id, sensor
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}"
		rpn = get_profile(get_sensor_config(multi_id, sensor)["profile"])["rpn"].sub("X", value.to_s)
		value_norm = solve_rpn(rpn)
		key = {"value" => value_norm,"timestamp" => Time.now.to_f}.to_json
		@redis.hset("#{path}.#{VALUE}", sensor, key)
		@redis.publish("#{path}:#{sensor}.#{VALUE}", value_norm)
		return true
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
					yield parse[MULTI].to_i, parse[SENS].to_i, JSON.parse(message)
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
					yield parse[MULTI].to_i, parse[SENS].to_i
				end
			end
		}
	end

	def on_new_config(&block)
		Thread.new{
			redis = Redis.new :host => @host, :port => @port
			redis.subscribe("config") do |on|
				on.message do |channel, message|
					yield JSON.parse(message)
				end
			end
		}
	end			
	
	private
	
	def solve_rpn(s)
		stack = []
		s.split(" ").each do |e|
			case e
				when "+"
					stack.push(stack.pop + stack.pop)
				when "-"
					stack.push(-stack.pop + stack.pop)
				when "*"
					stack.push(stack.pop * stack.pop)
				when "/"
					a, b = stack.pop, stack.pop
					stack.push(b / a)
				else
					stack.push(e.to_f)
			end
		end
		stack[0]
	end
end

