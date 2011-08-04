require './redis-interface-common.rb'
# TODO delete every hdel, hset : should be done by the demon

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
	
	# Register a sensor or an actuator.
	# @return [boolean] true if a demon was listening
	# @option config [String] :name Name of the device
	# @option config [String] :profile Profile associated to the device
	# @option config [Integer] :period Sensor only : Period beetween to sensor reading (in ms) (optional if the profile has a default period)
	# @option config [Integer, optional] :value Actuator only : Initial value
	# @param [Integer] multi_id Multiplexer's Id
	# @macro [new] type
	#  @param [Symbol] type Device type, can be :sensor or :actuator
	#
	def add type, multi_id, config
		raise ArgumentError, "Multiplexer Id should be an Integer" unless multi_id.is_a? Integer
		config.must_have(name: String, profile: String)
		case type
			when :sensor
				profile = get_profile :sensor, config[:profile]
				raise ArgumentError, "Profile #{config[:profile]} does not exist" unless profile
				profile.has_key?(:period)? config.can_have(period: Integer) : config.must_have(period: Integer)
#				profile.has_key?(:pin)? can_have[:pin] = Integer : must_have[:pin] = Integer #TODO implement default pin ?
			when :actuator
				config.can_have(value: Integer)
			else raise ArgumentError, "Type should be :sensor or :actuator"
		end
		@redis.publish(path(type, :config, multi_id), config.to_json) >= 1
	end
	
	# Unregister a sensor
	# @macro type
	# @return [boolean] true if a demon was listening
	def remove type, multi_id, pin
		path = path(type, :delete, multi_id)
		@redis.publish(path, pin) >= 1
	end
	
	# Register a sensor profile
	# 
	#
	def add_profile( args )#type, name, profile )
		args.must_have(type: Symbol, name: String, function: String)
		args.can_have(period: Integer, option1: Integer, option2: Integer)
		case args[:type]
			when :sensor
				args.must_have(unit: String)
				args.can_have(rpn: String, precision: Integer)
		end
		@redis.hset(path(args.delete(:type)), args.delete(:name), args.to_json)
	end
	
	# Unregister a profile
	# @return true if something was removed
	#
	def remove_profile( type, name )
		@redis.hdel(path(type), name) == 1
	end
	

end
