require './redis-interface-common.rb'
require 'logger'

# Contain methods userful for the demon : multiplexer's registration and dynamic callbacks of clients' messages
#
#

class Redis_interface_demon
	include Redis_interface_common
	
	def initialize(network, host = 'localhost', port = 6379, logger = Logger.new(nil))
		super(network, host, port)
		@log = logger
		@log.info("Demon started")
	end
	
	# Destroy the entire database and configuration
	#
	def flushdb
		@redis.flushdb
		@log.info("Flushing database")
	end

	# Assign a config to a multiplexer
	#
	def set_multi_config multi_id, config
		path = "#{@prefix}.#{MULTI}"
		@redis.hset("#{path}.#{CONF}", multi_id, config.to_json)
		@redis.publish("#{path}:#{multi_id}.#{CONF}", config.to_json)
		@log.debug("Registering multiplexer's configuration of #{multi_id} : #{config}")
	end
	
	# Publish a sensor's value
	#
	def publish_value(multi_id, sensor, value)
		return false unless knows? :sensor, multi_id, sensor
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{SENS}"
		config = get_config(:sensor, multi_id, sensor)
		if config == nil
			@log.error("Tried to publish a value from an unknown multiplexer : #{multi_id}")
			return false
		end
		profile = get_profile(:sensor, config[:profile])
		if profile == nil
			@log.error("Tried to publish a value from an unknown profile : #{config[:profile]} (multiplexer : #{multi_id})")
			return false
		end
		if profile.has_key? :rpn
			rpn = profile[:rpn].sub("X", value.to_s)
			value = solve_rpn(rpn)
		end
		key = {:value => value,:timestamp => Time.now.to_f}.to_json
		@redis.hset("#{path}.#{VALUE}", sensor, key)
		@redis.publish("#{path}:#{sensor}.#{VALUE}", value)
		return true
	end
	
		
	# Callback when a client request to add a sensor
	# block has 3 arguments : multiplexer's id, sensor's pin and sensor's config
	#
	def on_new_sensor(&block)
		Thread.new do
			redis = Redis.new :host => @host, :port => @port
			redis.psubscribe("#{@prefix}.#{MULTI}:*.#{SENS}:*.#{CONF}") do |on|
				on.pmessage do |pattern, channel, message|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ].symbolize_keys
					parse.merge!(JSON.s_parse(message))
					profile = get_profile :sensor, parse[:profile]
					if profile == nil
						@log.warn("A client tried to add a sensor with an unknown profile : #{parse[:profile]} (multiplexer : #{parse[:multiplexer]})")
						next
					end
					parse = {period: profile[:period]}.merge parse #default values
					# TODO vérifier validité de la config
					block.call(parse[:multiplexer], parse[:sensor], profile[:function], parse[:period], *[profile[:option1], profile[:option2]])
				end
			end
		end
	end
	
	# Callback when a client request to add an actu
	# block has 3 arguments : multiplexer's id, actu's pin and actu's profile
	# TODO : useless ?
	def on_new_actu(&block)
		Thread.new do
			redis = Redis.new :host => @host, :port => @port
			redis.psubscribe("#{@prefix}.#{MULTI}*.#{ACTU}:*.#{CONF}") do |on|
				on.pmessage do |pattern, channel, profile|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ]
					yield parse[MULTI].to_i, parse[ACTU].to_i, profile
				end
			end
		end
	end
	
	# Callback when a client request to delete a sensor
	# block has 2 arguments : multiplexer's id, sensor's pin
	#
	def on_deleted_sensor(&block)
		Thread.new do
			redis = Redis.new :host => @host, :port => @port
			redis.psubscribe("#{@prefix}.#{MULTI}:*.#{SENS}:*.#{DEL}") do |on|
				on.pmessage do |pattern, channel, message|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ].symbolize_keys
					#if not knows?(:sensor, parse[:multiplexer].to_i, parse[:sensor].to_i) #TODO, client already deleted it.
					#	@log.warn("A client tried to remove an unknown sensor : #{parse[:multiplexer]},#{parse[:sensor]}")
					#	next
					#end
					yield parse[:multiplexer].to_i, parse[:sensor].to_i
				end
			end
		end
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
