require './redis-interface-common.rb'

# Contain useful methods for the client : writing sensors' configuration, reading published values...
class Redis_interface_client
	include Redis_interface_common
	# Return the list of supported profile from a list of arduino functions
	#
	def support(functions)
		list_profiles(:actuator).merge(list_profiles(:sensor)).select { |name, profile|
			functions.include? profile[:function]
		}.keys
	end
	
	# Register description of a multiplexer. Return false if the multi doesn't exist
	#
	def set_description multi_id, description
		raise ArgumentError "Description must be a string" unless description.is_a?(String)
		return false unless knows_multi?(multi_id)
		path = "#{@prefix}.#{MULTI}"
		config = JSON.s_parse(@redis.hget("#{path}.#{CONF}", multi_id))
		config[:description] = description
		@redis.hset("#{path}.#{CONF}", multi_id, config.to_json)
		@redis.publish("#{path}:#{multi_id}.#{CONF}", config.to_json)
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
				profile.has_key?(:period)? can_have[:period] = Integer : must_have[:period] = Integer
				profile.has_key?(:pin)? can_have[:pin] = Integer : must_have[:pin] = Integer
			when :actuator then {}
		end
		raise_errors(must_have, can_have, config)
		config = {pin: profile[:pin], period: profile[:period]}.merge config
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{config.delete(:type)}"
		@redis.publish("#{path}:#{config[:pin]}.#{CONF}", config.to_json)
		@redis.hset("#{path}.#{CONF}", config[:pin], config.to_json)
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
	
	def set_actuator_state(multi_id, pin, state)
		return false unless (knows? :actuator, multi_id, pin)
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{ACTU}"
		@redis.hset("#{path}.#{VALUE}", pin, state)
		@redis.publish("#{path}:#{pin}.#{VALUE}", state)
	end
	
	def raise_errors(must_have, can_have, args)
		errors = []
		must_have.each do |argument, type|
			errors << "#{argument} is missing" unless args[argument]
			errors << "#{argument} should be #{type}" unless args[argument].is_a? type
		end
		can_have.each do |argument, type|
			errors << "#{argument} should be #{type}" if args.has_key?(argument) and not args[argument].is_a? type
		end
		raise ArgumentError, errors.join("\n") unless errors.size == 0
	end
	
	# Register a sensor profile
	#
	def add_profile( args )#type, name, profile )
		must_have = {:type => Symbol, :name => String, :function => String}
		can_have = {}
		case args[:type]
			when :sensor
				must_have.merge!({:unit => String})
				can_have.merge!({:rpn => String, :period => Integer, :pin => Integer, :option1 => Integer, :option2 => Integer})
			when :actuator
				can_have.merge!({:period => Integer})
		end
		raise_errors(must_have, can_have, args)
		@redis.hset("#{CONF}.#{args.delete(:type)}", args.delete(:name), args.to_json)
	end
	
	# Unregister a profile TODO : check if users ?
	#
end
