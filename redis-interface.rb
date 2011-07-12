=begin
- Multiplexer's config mean : {"description" => "descriptive goes here", "supported" => ["profile1", "profile2"]}
- Sensor's config mean : {"description" => "descriptive", "profile" => "profile_name", "period" => 1000 (ms)}
- Actuator's config mean : {"description" => "self explanatory", "profile" => "profile_name" }
- Actuator's profile mean : {"function" => "firm function", "period" => 200)}
- Sensor's profile mean : { "function" => "firmware function", "rpn" => "2 X *", "unit" => "Celsius"}
TODO : default period ? default pin ?
TODO : bug, on peut ajouter un actuator et un sensor sur le même pin, et la suppression de l'un entraîne la suppression de l'autre sur l'arduino et pas sur redisS
TODO vérifier la validité des config données à base de has_key
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
	
	# Return the list of supported profile from a list of arduino functions
	#
	def support(functions)
		list_profiles(:actuator).merge(list_profiles(:sensor)).select { |name, profile|
			functions.include? profile["function"]
		}.keys
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
		return false unless knows_multi?(multi_id) and description.is_a?(String)
		path = "#{@prefix}.#{MULTI}"
		config = JSON.parse(@redis.hget("#{path}.#{CONF}", multi_id))
		config["description"] = description
		@redis.hset("#{path}.#{CONF}", multi_id, config.to_json)
		@redis.publish("#{path}:#{multi_id}.#{CONF}", config.to_json)
		return true
	end
	
	# Return true if a multi is registered
	#
	def knows_multi? multi_id
		@redis.hexists("#{@prefix}.#{MULTI}.#{CONF}", multi_id)
	end
	
	##### Device management #####
	
	# Return true if the device exists, false if not.
	#
	def knows? type, multi_id, pin
		(knows_multi? multi_id) && @redis.hexists("#{@prefix}.#{MULTI}:#{multi_id}.#{type}.#{CONF}", pin)
	end
	
	# Return true if the config is valid
	#
	def is_device_config? type, config
		return false unless config["description"].is_a?(String) and config["profile"].is_a?(String)
		case type.to_s
			when SENS
				return false unless config["period"].is_a? Integer
				return true
			when ACTU
				return true
			else
				return false
			end
	end
	
	# Get a device's config
	#
	def get_config type, multi_id, pin
		return nil unless knows? type, multi_id, pin
		JSON.parse(@redis.hget("#{@prefix}.#{MULTI}:#{multi_id}.#{type}.#{CONF}", pin))
	end
	
	# Register a sensor.
	# return true if this was a success
	#
	def add type, multi_id, pin, config
		return false unless (is_device_config? type, config)
		return false unless (knows_multi? multi_id) && (knows_profile? type, config[PROF])
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{type}"
		@redis.publish("#{path}:#{pin}.#{CONF}", config.to_json)
		@redis.hset("#{path}.#{CONF}", pin, config.to_json)
		return true
	end
	
	# Unregister a sensor. Return true if something was removed
	# TODO does not publish if no multi ?
	def remove type, multi_id, pin
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{type}"
		set_actuator_state(multi_id, pin, 0) if type.to_s == ACTU
		@redis.publish("#{path}:#{pin}.#{DEL}", pin)
		@redis.hdel("#{path}.#{CONF}", pin) == 1
	end
	
	# Get all sensors config of a multi, in form {pin => config}
	# Return {} if there were no sensor, return nil if the multi does not exists
	#
	def list type, multi_id
		return nil unless knows_multi? multi_id
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{type}.#{CONF}"
		Hash[*@redis.hgetall(path).collect {|id, config| [id.to_i, JSON.parse(config)]}.flatten]
	end

	
	##### Actuator management #####

	def set_actuator_state(multi_id, pin, state)
		return false unless (knows? :actuator, multi_id, pin)
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{ACTU}"
		@redis.hset("#{path}.#{VALUE}", pin, state)
		@redis.publish("#{path}:#{pin}.#{VALUE}", state)
	end
	
	##### Profile utilitie #####
	
	# Return true if the profile exist
	#
	def knows_profile?( type, name )
		@redis.hexists("#{CONF}.#{type}", name)
	end
	
	# Return true if the profile is a good profile
	#
	def is_a_profile? (type, profile)
		return false unless (profile["function"].is_a?(String))
		case type.to_s
			when SENS
				return false unless is_a_rpn?(profile["rpn"])
				return false unless profile["unit"].is_a?(String)
				return true
			when ACTU
				return false if (profile.has_key?("period") and not profile["period"].is_a?(Integer))
				return true
			else
				return false
		end
	end
	
	# Register a sensor profile
	#
	def add_profile( type, name, profile )
		return false unless is_a_profile?(type, profile)
		@redis.hset("#{CONF}.#{type}", name, profile.to_json)
	end
	
	# Unregister a profile TODO : check if users ?
	#
	
	# get all sensor/actuators profiles in a hash {name => profile}
	# Parameter can be :sensor or :actuator
	#
	def list_profiles (type)
		list = @redis.hgetall("#{CONF}.#{type}")
		list.each { |name, profile| list[name] = JSON.parse(profile) }
	end
	
	# With string parameter : get a sensor profile
	# Parameter can be :sensor or :actuator
	#
	def get_profile(type, profile)
		return nil unless knows_profile?(type, profile)
		JSON.parse(@redis.hget("#{CONF}.#{type}", profile))
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
					yield parse[MULTI].to_i, parse[type.to_s].to_i, valeur.to_f
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
		return false unless knows? :sensor, multi_id, sensor
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}"
		rpn = get_profile(:sensor, get_config(:sensor, multi_id, sensor)["profile"])["rpn"].sub("X", value.to_s)
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
	
	# Callback when a client request to add an actu
	# block has 3 arguments : multiplexer's id, actu's pin and actu's profile
	# TODO : useless ?
	def on_new_actu(&block)
		Thread.new{
			redis = Redis.new :host => @host, :port => @port
			redis.psubscribe("#{@prefix}.#{MULTI}*.#{ACTU}:*.#{CONF}") do |on|
				on.pmessage do |pattern, channel, profile|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ]
					yield parse[MULTI].to_i, parse[ACTU].to_i, profile
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
	
	def is_a_rpn?(rpn)
		return false unless (s = String.try_convert(rpn))
		s.split(" ").each do |e|
			return false unless (e.is_numeric? or ["+", "-", "*", "/", "X"].include? e)
		end
		return true
	end

	
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
class String
  def is_integer?
    begin Integer(self) ; true end rescue false
  end
  def is_numeric?
    begin Float(self) ; true end rescue false
  end
end


