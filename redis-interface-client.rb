require './redis-interface-common.rb'
# TODO delete every hdel, hset : should be done by the demon

# Contain useful methods for the client : writing sensors' configuration, reading published values...
class Redis_interface_client
	include Redis_interface_common
	def initialize(network, host = 'localhost', port = 6379)
		load(network, host, port)
	end
	# Return the list of supported profile from a list of arduino functions
	#
	def support(functions)
		list_profiles(:actuator).merge(list_profiles(:sensor)).select { |name, profile|
			functions.include? profile[:function]
		}.keys
	end
	
	# Register description of a multiplexer. Return false if the multi doesn't exist
	# Publication inutile ?
	#
	def set_description multi_id, description
		raise ArgumentError "Description must be a string" unless description.is_a?(String)
		return false unless knows_multi?(multi_id)
		path = "#{@prefix}.#{MULTI}.#{CONF}"
		config = JSON.s_parse(@redis.hget(path, multi_id))
		config[:description] = description
		@redis.hset(path, multi_id, config.to_json)
		#@redis.publish("#{path}:#{multi_id}.#{CONF}", config.to_json)
		return true
	end
	
	# Register a sensor or an actuator.
	# return true if this was a success
	#
	def add type, multi_id, args#type, multi_id, pin, config
		config = args.dup
		config[:type] = type
		config[:multiplexer] = multi_id
		must_have = {type: Symbol, name: String, profile: String, multiplexer: Integer}
		can_have = {}
		profile = {}
		case type
			when :sensor
				profile = get_profile :sensor, args[:profile]
				profile.has_key?(:period)? can_have[:period] = Integer : must_have[:period] = Integer #TODO profile non checké
				profile.has_key?(:pin)? can_have[:pin] = Integer : must_have[:pin] = Integer
			when :actuator then {}
			else raise ArgumentError, "Type should be :sensor or :actuator"
		end
		raise_errors(must_have, can_have, config)
		#config = {pin: profile[:pin], period: profile[:period]}.merge config #inutile normalement
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{config.delete(:type)}.#{CONF}"
		@redis.publish(path, config.to_json)
		#@redis.hset("#{path}.#{CONF}", config[:pin], config.to_json)
		return true
	end
	
	# Unregister a sensor. Return true if something was removed
	# TODO does not publish if no multi ?
	def remove type, multi_id, pin
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{type}.#{DEL}"
		#set_actuator_state(multi_id, pin, 0) if type.to_s == ACTU and get_actuator_state(multi_id, pin) TODO should be done by demon
		@redis.publish(path, pin)
		#@redis.hdel("#{path}.#{CONF}", pin) == 1
	end
	
	# Register a sensor profile
	#
	def add_profile( args )#type, name, profile )
		must_have = {type: Symbol, name: String, function: String}
		can_have = {:period => Integer, :option1 => Integer, :option2 => Integer}
		case args[:type] #TODO :type non checké
			when :sensor
				must_have[:unit] = String
				can_have[:rpn] = String
				can_have[:precision] = Integer
			when :actuator
				{}
		end
		raise_errors(must_have, can_have, args)
		@redis.hset("#{CONF}.#{args.delete(:type)}", args.delete(:name), args.to_json)
	end
	
	# Unregister a profile TODO : check if users ?
	#
	def remove_profile( name )
		raise NotImplementedError
	end
	
	private
	
	# Check if options are present and are of good type
	#
	def raise_errors(must_have, can_have, args)
		errors = []
		must_have.each do |argument, type|
			errors << "#{argument} is missing" unless args[argument]
			errors << "#{argument} should be #{type}" unless args[argument].is_a? type
		end
		can_have.each do |argument, type|
			errors << "#{argument} should be #{type}" if args.has_key?(argument) and not args[argument].is_a? type
		end
		raise ArgumentError, errors.join(", ") unless errors.size == 0
	end
end
