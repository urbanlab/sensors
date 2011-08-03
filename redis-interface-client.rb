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
	#@return [Array[String]] the profiles
	#
	def support(functions)
		list_profiles(:actuator).merge(list_profiles(:sensor)).select { |name, profile|
			functions.include? profile[:function]
		}.keys
	end
	
	# Register description of a multiplexer.
	#@return [boolean] true if the description was succefully changed
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
	#@return [boolean] true if a demon was listening
	#@macro [new] type
	#@param [Symbol] type Device type, can be :sensor or :actuator
	#
	def add type, multi_id, args#type, multi_id, pin, config
		config = args.dup
		config[:type] = type
		config[:multiplexer] = multi_id
		config.must_have(type: Symbol, name: String, profile: String, multiplexer: Integer)
		profile = {}
		case type
			when :sensor
				profile = get_profile :sensor, config[:profile]
				profile.has_key?(:period)? config.can_have(period: Integer) : config.must_have(period: Integer) #TODO profile non checké
#				profile.has_key?(:pin)? can_have[:pin] = Integer : must_have[:pin] = Integer #TODO implement default pin ?
			#when :actuator then {}
			#else raise ArgumentError, "Type should be :sensor or :actuator"
		end
		path = path(config.delete(:type), :config, multi_id)
		@redis.publish(path, config.to_json) >= 1
	end
	
	# Unregister a sensor
	#@macro type
	#@return true if a demon was listening
	# TODO does not publish if no multi ?
	def remove type, multi_id, pin
		path = path(type, :delete, multi_id)
		#set_actuator_state(multi_id, pin, 0) if type.to_s == ACTU and get_actuator_state(multi_id, pin) TODO should be done by demon
		@redis.publish(path, pin) >= 1
		#@redis.hdel("#{path}.#{CONF}", pin) == 1
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
	#@return true if something was removed
	#
	def remove_profile( type, name )
		@redis.hdel(path(type), name) == 1
	end
	

end
