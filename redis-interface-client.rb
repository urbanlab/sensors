$:.unshift(File.dirname(__FILE__) + '/') unless $:.include?(File.dirname(__FILE__) + '/')
require 'redis-interface-common'

# Contain useful methods for the client : writing sensors' configuration, reading published values...
#
class Redis_interface_client
	include Redis_interface_common
	def initialize(network, host = 'localhost', port = 6379)
		load(network, host, port)
	end
	# Return the list of supported profile from a list of arduino functions
	# @return [Array<String>] the profiles
	#
	def support(functions)
		list_profiles(:actuator).merge(list_profiles(:sensor)).select { |name, profile|
			functions.include? profile[:function]
		}.keys
	end
	
	# Register description of a multiplexer.
	# @return [boolean] true if the description was succefully changed
	#
	#
	def set_description multi_id, description
		raise ArgumentError "Description must be a string" unless description.is_a?(String)
		return false unless knows_multi?(multi_id)
		config = JSON.s_parse(@redis.hget(path(), multi_id))
		config[:description] = description
		@redis.hset(path(), multi_id, config.to_json)
		#@redis.publish("#{path}:#{multi_id}.#{CONF}", config.to_json)
		return true
	end
	
	# Associate a multi to the network
	# @param [Integer] multi_id Id of the multi
	#
	def take multi_id
		raise ArgumentError "multi_id must be a Integer" unless multi_id.is_a?(Integer)
		@redis.publish(path(), {multiplexer: multi_id, network: @network}.to_json)
	end
	
	# Register a sensor or an actuator.
	# @return [boolean] true if a demon was listening
	# @option config [String] :name Name of the device
	# @option config [String] :profile Profile associated to the device
	# @option config [Integer] :period Sensor only : Period beetween to sensor reading (in ms) (optional if the profile has a default period)
	# @option config [Integer, optional] :value Actuator only : Initial value
	# @option config [Integer] :pin Pin where the device is plugged
	# @param [Integer] multi_id Multiplexer's Id
	# @param [Symbol] type Device type, can be :sensor or :actuator
	#
	def add type, multi_id, config = {}
		raise ArgumentError, "Multiplexer Id should be an Integer" unless multi_id.is_a? Integer
		case type
			when :sensor
				config.must_have(SENS_CONF[:necessary])
				config.can_have(SENS_CONF[:optional])
				profile = get_profile :sensor, config[:profile]
				raise ArgumentError, "Profile #{config[:profile]} does not exist" unless profile
				config.must_have(period: Integer) unless profile[:period].is_a? Integer
#				profile.has_key?(:pin)? can_have[:pin] = Integer : must_have[:pin] = Integer #TODO implement default pin ?
				@redis.publish(path(type, :config, multi_id), config.to_json) >= 1
			when :actuator
				config.must_have(ACTU_CONF[:necessary])
				config.can_have(ACTU_CONF[:optional])
				@redis.hset(path(type, :config, multi_id), config.delete(:pin), config.to_json)
			else raise ArgumentError, "Type should be :sensor or :actuator"
		end
	end
	
	# Unregister a sensor
	# @param [Symbol] type Device type, can be :sensor or :actuator
	# @param [Integer] multi_id Id of the multiplexer
	# @param [Integer] pin Pin where the device was plugged
	# @return [boolean] true if a demon was listening
	#
	def remove type, multi_id, pin
		path = path(type, :delete, multi_id)
		@redis.publish(path, pin) >= 1
	end
	
	# Register a sensor profile
	# @param [Symbol] type Profile type, can be :sensor or :actuator
	# @param [String] name Profile name
	# @option profile [String] :function Arduino's function the profile uses
	# @option profile [Integer, optional] :period default period
	# @option profile [Integer, optional] :option1 first function's argument (see its description)
	# @option profile [Integer, optional] :option2 second function's argument (see its description)
	# @option profile [String] :unit unit of the sensor's value (sensor only)
	# @option profile [String, optional] :rpn optional RPN transformation to apply to raw value (sensor only)
	# @option profile [Integer, optional] :precision optional precision of the sensor (eg. 3 for value like 334.411, -1 for value like 330)
	#
	def add_profile( type, name, profile = {} )
		raise ArgumentError, "Name should be a String" unless name.is_a? String
		case type
			when :sensor
				profile.must_have(SENS_PROFILE[:necessary])
				profile.can_have(SENS_PROFILE[:optional])
			when :actuator
				profile.must_have(ACTU_PROFILE[:necessary])
				profile.can_have(ACTU_PROFILE[:optional])
			else raise ArgumentError, "Type should be :sensor or :actuator"
		end
		@redis.hset(path(type), name, profile.to_json)
	end
	
	# Unregister a profile
	# @return true if something was removed
	#
	def remove_profile( type, name )
		@redis.hdel(path(type), name) == 1
	end
	

end
