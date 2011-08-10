require 'rubygems'
require 'json'
#require 'redis/connection/hiredis'
require 'redis'
require 'extensions'

# Contain common methods between the server and the client : static information reading
#
module Redis_interface_common
	# Definition of a sensor config (note that the period is necessary if not defined in the profile)
	SENS_CONF = {necessary: {name: String, profile: String, pin: Integer},
				 optional:   {period: Integer}}
	# Definition of an actuator config
	ACTU_CONF = {necessary: {name: String, profile: String, pin: Integer},
				 optional:   {period: Integer}}
	# Definition of a sensor profile
	SENS_PROFILE = {necessary: {function: String, unit: String},
					optional:  {period: Integer, option1: Integer, option2: Integer, rpn: :is_a_rpn?, precision: Integer}}
	# Definition of an actuator profile
	ACTU_PROFILE = {necessary: {function: String},
					optional:  {period: Integer, option1: Integer, option2: Integer}}
	
	# Common function that should be load by initilize of classes using the
	# module
	#
	def load(network, host = 'localhost', port = 6379)
		@host = host
		@port = port
		@redis = Redis.new host: host, port: port
		@redis.set("test", "ohohoh") #bypass ruby optimisation to catch exceptions at launch
		@network = network
	end
	
	# get all the multiplexers' config
	# @return [Hash] list in form +{id => config}+
	#
	def list_multis
		configs = @redis.hgetall(path())
		return Hash[*configs.collect{|id, conf| [id.to_i, JSON.s_parse(conf)]}.flatten]
	end
	
	# get a multiplexer's config
	# @return [Hash] config of the multi or nil if it doesn't exists or invalid
	#
	def get_multi_config( multi_id )
		return nil unless knows_multi? multi_id
		begin
			JSON.s_parse(@redis.hget(path(), multi_id))
		rescue Exception => e
			return nil
		end
	end
	
	# @return true if a multi is registered
	#
	def knows_multi? multi_id
		@redis.hexists(path(), multi_id)
	end
	
	# @return true if the device exists, false if not.
	#
	def knows? type, multi_id, pin
		(knows_multi? multi_id) && @redis.hexists(path(type, :config, multi_id), pin)
	end
	
	# Get a device's config
	# @return [Hash] Hash representing the config
	# @return [nil] if invalid or unknown pin or multi
	#
	def get_config type, multi_id, pin
		return nil unless knows? type, multi_id, pin
		begin
			JSON.s_parse(@redis.hget(path(type, :config, multi_id), pin))
		rescue Exception => e
			return nil
		end
	end
	
	# Get all sensors config of a multi, in form +{pin => config}+
	# @return [Hash] List of devices in form +{pin => config}+
	# @return [nil] if the multi does not exists or invalid datas
	#
	def list type, multi_id
		return nil unless knows_multi? multi_id
		path = path(type, multi_id)
		begin
			Hash[*@redis.hgetall(path).collect {|id, config| [id.to_i, JSON.s_parse(config)]}.flatten]
		rescue Exception => e
			return nil
		end
	end
	
	# Get the value of a sensor
	# @return [Hash] with keys :value (normalized), :timestamp (when the value was mesured), :name and :unit
	# @return [nil] if the sensor or the multi doesn't exist
	def get_sensor_value multi_id, pin
		return nil unless knows? :sensor, multi_id, pin
		hash = @redis.hgetall(path(:sensor, :value, multi_id, pin)).symbolize_keys
		return {value: hash[:value].to_f, timestamp: hash[:timestamp].to_f, name: hash[:name], unit: hash[:unit]}
	end
	
	# Get the state of an actuator
	# @return [boolean] True for on, false for off, or nil if the actuator is unknown
	#
	def get_actuator_state(multi_id, pin)
		return nil unless knows?(:actuator, multi_id, pin)
		@redis.hget(path(:actuator, :value, multi_id, pin))
	end
	
	# Activate or deactivate an actuator
	#
	def set_actuator_state(multi_id, pin, state)
		return false unless (knows? :actuator, multi_id, pin)
		@redis.publish(path(:actuator, :value, multi_id, pin), state)
	end
	
	# @return [boolean] true if the profile exists
	#
	def knows_profile?( type, name )
		@redis.hexists(path(type), name)
	end
	
	# get all sensor/actuators profiles
	# @return [Hash] in form +{name => profile}+
	# @macro [new] type
	#   @param [Symbol] type can be :sensor or :actuator
	#
	def list_profiles (type)
		list = @redis.hgetall(path(type))
		list.each { |name, profile| list[name] = JSON.s_parse(profile) }
	end
	
	# Get a profile
	# @macro type
	# @param [String] profile the name of the profile
	# @return [Hash] the profile
	# @return [nil] if unknown profile or invalid datas
	#
	def get_profile(type, profile)
		return nil unless knows_profile?(type, profile)
		begin
			JSON.s_parse(@redis.hget(path(type), profile))
		rescue Exception => e
			return nil
		end
	end
	
	# Callback when a value is published on redis.
	# @macro type
	# @param [String, Integer] multi id of the multiplexer you need to listen to, or '*' for all multiplexers
	# @param [String, Integer] pin Pin you need to listen to, or '*' for all the pins
	# @yield [multi_id, pin, value, unit, name] Processing of the published value for type = :sensor
	# @yield [multi_id, pin, value] Processing of the published value for type = :actuator
	# TODO solidification pour le démon
	#
	def on_published_value(type, multi = "*", pin = "*")
		Thread.new do
			redis = Redis.new
			redis.psubscribe(path(type, :value, multi, pin)) do |on|
				on.pmessage do |pattern, channel, value|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ].symbolize_keys
					case type
						when :sensor
							parse.merge!(JSON.s_parse(value))
							yield parse[:multiplexer].to_i, parse[type].to_i, parse[:value].to_f, parse[:unit], parse[:name]
						when :actuator
							yield parse[:multiplexer].to_i, parse[type].to_i, value.to_i
					end
				end
			end
		end
	end
	
	private
	
	# Generate redis path
	# With no argument : path of the multiplexers' conf hash
	# With 1 : :sensor or :actuator : path of the profiles' hash
	# With 2 : first : :sensor or :actuator, 2nd : integer. Path
	# of the list of sensors' config of a multiplexer
	# With 3 : 1st : :sensor or :actuator, 2nd : :config, :delete, 3rd : multi_id.
	# Path of device channel
	# With 4 : 1st : :sensor or :actuator, 2nd : :config or :delete or :value, 3rd : multi_id, 4th : pin
	#
	def path(*args)
		case args.size
			when 0 then "config.multiplexer"
			when 1 then "config.#{args[0]}"
			when 2 then "network:#@network.multiplexer:#{args[1]}.#{args[0]}.config"
			when 3 then "network:#@network.multiplexer:#{args[2]}.#{args[0]}.#{args[1]}"
			when 4 then "network:#@network.multiplexer:#{args[2]}.#{args[0]}:#{args[3]}.#{args[1]}"
		end
	end
end

