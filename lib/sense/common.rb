require 'rubygems'
require 'json'
begin require('redis/connection/hiredis'); rescue LoadError; end
require 'redis'

require 'sense/extensions'

module Sense
	# Contain common methods between the server and the client : static information reading
	#
	module Common
		# Definition of a device config (note that the sensor's period is necessary if not defined in the profile)
		#
		CONFIG =	{ sensor:
						{necessary: {name: String, profile: String, pin: Integer},
					 	optional:   {period: Integer}},
					 actuator:
					 	{necessary: {name: String, profile: String, pin: Integer},
					 	optional:   {period: Integer}}
					}

		# Definiction of a device profile
		#
		PROFILE =	{
						sensor:
							{necessary: {function: String, unit: String},
							optional:  {period: Integer, option1: Integer, option2: Integer, rpn: :is_a_rpn?, precision: Integer}},
						actuator:
							{necessary: {function: String},
							optional:  {period: Integer, option1: Integer, option2: Integer}}
					}
					
		# Prefix of every message or key
		#
		PREFIX = "sense"
	
		# Common function that should be load by initilize of classes using the
		# module
		# @param [Integer] network Network identifier
		# @param [String] host Redis host
		# @param [Integer] port Redis port
		#
		def load(network, host = 'localhost', port = 6379)
			@host = host
			@port = port
			@redis = Redis.new host: host, port: port
			@redis.set("test", "ohohoh") #bypass ruby optimisation to catch exceptions at launch
			@network = network
		end
	
		# get all the multiplexers' config
		# @param [Integer, String] network Network identifier of the multi, or '*'
		# @return [Hash] list in form +{id => config}+
		#
		def list_multis(network = @network)
			configs = Hash[*@redis.hgetall(path()).collect{|id, conf| [id.to_i, JSON.s_parse(conf)]}.flatten]
			if network.is_a? Integer
				return configs.select{|id, conf| conf[:network] == network}
			elsif network == '*'
				return configs
			else return {}
			end
		end
	
		# get a multiplexer's config
		# @return [Hash] config of the multi or nil if it doesn't exists or invalid
		# @param [Integer, String] multi Id or name of the multiplexer
		#
		def get_multi_config( multi )
			multi = get_multi_id(multi)
			if multi.is_a? Integer
				return nil unless knows_multi? multi
				begin
					JSON.s_parse(@redis.hget(path(), multi))
				rescue Exception => e
					return nil
				end
			else
				return nil
			end
		end
		
		# Get id of a multiplexer by its name or by its id
		# @param [Integer, String] multi id or name of the multiplexer
		# @return [Integer] id corresponding
		# @return nil if nothing found
		#
		def get_multi_id( multi )
			return multi if multi.is_a? Integer
			id, config = list_multis('*').find{|id, conf| conf[:description] == multi}
			return id
		end
		
		# Get pin of a multiplexer from it's multiplexer and device
		# @param [Symbol] type :actuator or :sensor
		# @param [Integer, String] multi id or name of the multiplexer the device is plugged on
		# @param [Integer, String] device pin or name of the device
		#
		def get_pin(type, multi, device)
			return device if device.is_a? Integer
			dev_list = list(type, multi)
			return nil unless dev_list.is_a? Hash
			pin, conf = dev_list.find{|pin, conf| conf[:name] == device}
			return pin
		end
		
		# @return true if a multi is registered
		# @param [Integer, String] multi id or name of the multiplexer
		#
		def knows_multi? multi
			@redis.hexists(path(), get_multi_id(multi))
		end
	
		# @return true if a multi is registered and belong to my network
		# @param [Integer, String] multi id or name of the multiplexer
		#
		def mine? multi
			c = get_multi_config(multi)
			return false if (not c) or (not c[:network])
			return c[:network] == @network
		end
	
		# @return true if the device exists, false if not.
		# @param [Symbol] type :actuator or :sensor
		# @param [Integer, String] multi id or name of the multiplexer the device is plugged in
		# @param [Integer, String] pin pin or name of the device
		#
		def knows? type, multi, pin
			(mine? multi) && @redis.hexists(path(type, :config, get_multi_id(multi)), pin)
		end
	
		# Get a device's config
		# @return [Hash] Hash representing the config
		# @return [nil] if invalid or unknown pin or multi
		# @param [Symbol] type :actuator or :sensor
		# @param [Integer, String] multi id or name of the multiplexer
		# @param [Integer, string] pin pin or name of the device
		#
		def get_config type, multi, pin
			multi_id = get_multi_id multi
			pin = get_pin type, multi_id, pin
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
		# @param [Symbol] type :actuator or :sensor
		# @param [Integer, String] multi id or name of the multiplexer
		#
		def list type, multi
			multi_id = get_multi_id(multi)
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
		# @param [Integer, String] multi id or name of the multiplexer
		# @param [Integer, String] pin pin or name of the sensor
		def get_sensor_value multi, pin
			multi_id = get_multi_id(multi)
			pin = get_pin(:sensor, multi_id, pin)
			return nil unless knows? :sensor, multi_id, pin
			hash = @redis.hgetall(path(:sensor, :value, multi_id, pin)).symbolize_keys
			return {value: hash[:value].to_f, timestamp: hash[:timestamp].to_f, name: hash[:name], unit: hash[:unit]}
		end
	
		# Get the state of an actuator
		# @return [boolean] True for on, false for off, or nil if the actuator is unknown
		# @param [Integer, String] multi id or name of the multiplexer
		# @param [Integer, String] pin pin or name of the actuator
		#
		def get_actuator_state(multi, pin)
			multi_id = get_multi_id(multi)
			pin = get_pin(:actuator, multi_id, pin)
			return nil unless knows?(:actuator, multi_id, pin)
			@redis.hget(path(:actuator, :value, multi_id, pin))
		end
	
		# @return [boolean] true if the profile exists
		# @param [Symbol] type :actuator or :sensor
		# @param [String] name name of the profile
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
			network_path(@network, *args)
		end
		
		# Like path, with personalized network
		#
		def network_path(network, *args)
			case args.size
				when 0 then "#{PREFIX}.config.multiplexer"
				when 1 then "#{PREFIX}.config.#{args[0]}"
				when 2 then "#{PREFIX}.network:#{network}.multiplexer:#{args[1]}.#{args[0]}.config"
				when 3 then "#{PREFIX}.network:#{network}.multiplexer:#{args[2]}.#{args[0]}.#{args[1]}"
				when 4 then "#{PREFIX}.network:#{network}.multiplexer:#{args[2]}.#{args[0]}:#{args[3]}.#{args[1]}"
			end
		end
	end
end
