require 'rubygems'
require 'json'
require 'redis/connection/hiredis'
require 'redis'

# Contain common methods between the server and the client : static information reading
#
module Redis_interface_common
	PREFIX = "network"
	MULTI  = "multiplexer"
	SENS   = "sensor"
	ACTU   = "actuator"
	VALUE  = "value"
	CONF   = "config"
	DEL    = "delete"
	PROF   = "profile"
	
	def load(network, host = 'localhost', port = 6379)
		@host = host
		@port = port
		@redis = Redis.new :host => host, :port => port
		@redis.set("test", "ohohoh") #bypass ruby optimisation to catch exceptions at launch
		@network = network
		@prefix = "#{PREFIX}:#{@network}"
	end
	
	# get all the multiplexers config in a hash {id => config}
	#
	def list_multis
		configs = @redis.hgetall(path())
		return Hash[*configs.collect{|id, conf| [id.to_i, JSON.s_parse(conf)]}.flatten]
	end
	
	# get the multiplexer config or nil if does no exist
	#
	def get_multi_config( multi_id )
		return nil unless knows_multi? multi_id
		JSON.s_parse(@redis.hget(path(), multi_id))
	end
	
	# Return true if a multi is registered
	#
	def knows_multi? multi_id
		@redis.hexists(path(), multi_id)
	end
	
	# Return true if the device exists, false if not.
	#
	def knows? type, multi_id, pin
		(knows_multi? multi_id) && @redis.hexists(path(type, :config, multi_id, pin), pin)
	end
	
	# Get a device's config
	#
	def get_config type, multi_id, pin
		return nil unless knows? type, multi_id, pin
		JSON.s_parse(@redis.hget(path(type, :config, multi_id), pin))
	end
	
	# Get all sensors config of a multi, in form {pin => config}
	# Return {} if there were no sensor, return nil if the multi does not exists
	#
	def list type, multi_id
		return nil unless knows_multi? multi_id
		path = path(type, multi_id)
		Hash[*@redis.hgetall(path).collect {|id, config| [id.to_i, JSON.s_parse(config)]}.flatten]
	end
	
	# Return an array of [value, time] where time is the date when
	# the value was received. Return nil if the sensor doesn't
	# exists
	#
	def get_sensor_value multi_id, pin
		return nil unless knows? :sensor, multi_id, pin
		hash = @redis.hgetall(path(:sensor, :value, multi_id, pin)).symbolize_keys
		return hash[:value].to_f, hash[:timestamp].to_f
	end
	
	# Return the current state of the actuator (true for on, false for off)
	# or nil if the actuator is unknown
	#
	def get_actuator_state(multi_id, pin)
		return nil unless knows?(:actuator, multi_id, pin)
		@redis.hget(path(:actuator, :value, multi_id, pin))
	end
	
	def set_actuator_state(multi_id, pin, state)
		return false unless (knows? :actuator, multi_id, pin)
		@redis.publish(path(:actuator, :value, multi_id, pin), state)
	end
	
	# Return true if the profile exist
	#
	def knows_profile?( type, name )
		@redis.hexists(path(type), name)
	end
	
	# get all sensor/actuators profiles in a hash {name => profile}
	# Parameter can be :sensor or :actuator
	#
	def list_profiles (type)
		list = @redis.hgetall(path(type))
		list.each { |name, profile| list[name] = JSON.s_parse(profile) }
	end
	
	# With string parameter : get a sensor profile
	# Parameter can be :sensor or :actuator
	#
	def get_profile(type, profile)
		return nil unless knows_profile?(type, profile)
		JSON.s_parse(@redis.hget(path(type), profile))
	end
	
	# Callback when a value is published on redis.
	# Type might be :sensor or :actuator
	# block has 3 arguments : multiplexer's id, sensor's pin, value
	# TODO unknown actu
	#
	def on_published_value(type, multi = "*", pin = "*") # :yield: multi_id, sensor_id, value
		Thread.new do
			redis = Redis.new
			redis.psubscribe(path(type, :value, multi, pin)) do |on|
				on.pmessage do |pattern, channel, value|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ].symbolize_keys
					yield parse[:multiplexer].to_i, parse[type].to_i, value.to_f
				end
			end
		end
	end
	
	# Generate redis path
	# With no argument : path of the multiplexers' conf hash
	# With 1 : :sensor or :actuator : path of the profiles' hash
	# With 2 : first : :sensor or :actuator, 2nd : integer. Path
	# of the list of sensors' config of a multiplexer
	# With 3 : 1st : :sensor or :actuator, 2nd : :config, :delete, 3rd : multi_id.
	# Path of device channel
	# With 4 : 1st : :sensor or :actuator, 2nd : :config or :delete or :value, 3rd : multi_id, 4th : pin
	#TODO delete
	def path(*args)
		case args.size
			when 0 then "#@prefix.#{MULTI}.#{CONF}"
			when 1 then "#{CONF}.#{args[0]}"
			when 2 then "#@prefix.#{MULTI}:#{args[1]}.#{args[0]}.#{CONF}"
			when 3 then "#@prefix.#{MULTI}:#{args[2]}.#{args[0]}.#{args[1]}"
			when 4 then "#@prefix.#{MULTI}:#{args[2]}.#{args[0]}:#{args[3]}.#{args[1]}"
		end
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

# Stolen from rails source
class Hash
	def symbolize_keys
		inject({}) do |options, (key, value)|
			options[(key.to_sym rescue key) || key] = value
			options
		end
	end
	
	def integerize_keys!
		self.keys.each do |key|
			self[key.to_i] = self[key]
			self.delete key
		end
		self
	end
	
	def symbolize_keys!
		self.replace(self.symbolize_keys)
	end

	def recursive_symbolize_keys!
		symbolize_keys!
		# symbolize each hash in .values
		values.each{|h| h.recursive_symbolize_keys! if h.is_a?(Hash) }
		# symbolize each hash inside an array in .values
		values.select{|v| v.is_a?(Array) }.flatten.each{|h| h.recursive_symbolize_keys! if h.is_a?(Hash) }
		self
	end
end

module JSON
	class << self
		def s_parse(source, opts = {})
			result = Parser.new(source, opts).parse
			result.recursive_symbolize_keys! if result.is_a? Hash
		end
	end
end

