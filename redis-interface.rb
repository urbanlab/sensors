=begin
- Multiplexer's config mean : {"description" => "descriptive goes here", "supported" => ["profile1", "profile2"]}
- Sensor's config mean : {"description" => "descriptive", "profile" => "profile_name", "period" => 1000 (ms)}
- Actuator's config mean : {"description" => "self explanatory", "profile" => "profile_name" }
- Actuator's profile mean : {"function" => "firm function", "period" => 200)}
- Sensor's profile mean : { "function" => "firmware function", "rpn" => "2 X *", "unit" => "Celsius", ("defaultperiod" => 1000, "defaultpin" => 8, "option1" => 33, "option2" => 65)}
TODO : bug, on peut ajouter un actuator et un sensor sur le même pin, et la suppression de l'un entraîne la suppression de l'autre sur l'arduino et pas sur redisS
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
			functions.include? profile[:function]
		}.keys
	end
	
	##### Multiplexer management #####
	

	# get all the multiplexers config in a hash {id => config}
	#
	def list_multis
		configs = @redis.hgetall("#{@prefix}.#{MULTI}.#{CONF}")
		return Hash[*configs.collect{|id, conf| [id.to_i, JSON.s_parse(conf)]}.flatten]
	end
	
	# get the multiplexer config or nil if does no exist
	#
	def get_multi_config( multi_id )
		return nil unless knows_multi? multi_id
		JSON.s_parse(@redis.hget("#{@prefix}.#{MULTI}.#{CONF}", multi_id))
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

	# Get a device's config
	#
	def get_config type, multi_id, pin
		return nil unless knows? type, multi_id, pin
		JSON.s_parse(@redis.hget("#{@prefix}.#{MULTI}:#{multi_id}.#{type}.#{CONF}", pin))
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
	
	# Get all sensors config of a multi, in form {pin => config}
	# Return {} if there were no sensor, return nil if the multi does not exists
	#
	def list type, multi_id
		return nil unless knows_multi? multi_id
		path = "#{@prefix}.#{MULTI}:#{multi_id}.#{type}.#{CONF}"
		Hash[*@redis.hgetall(path).collect {|id, config| [id.to_i, JSON.s_parse(config)]}.flatten]
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
	
	# get all sensor/actuators profiles in a hash {name => profile}
	# Parameter can be :sensor or :actuator
	#
	def list_profiles (type)
		list = @redis.hgetall("#{CONF}.#{type}")
		list.each { |name, profile| list[name] = JSON.s_parse(profile) }
	end
	
	# With string parameter : get a sensor profile
	# Parameter can be :sensor or :actuator
	#
	def get_profile(type, profile)
		return nil unless knows_profile?(type, profile)
		JSON.s_parse(@redis.hget("#{CONF}.#{type}", profile))
	end
	
	##### Callbacks #####
	
	# Callback when a value is published on redis.
	# Type might be :sensor or :actuator
	# block has 3 arguments : multiplexer's id, sensor's pin, value
	#
	def on_published_value(type, multi = "*", pin = "*", &block)
		Thread.new{
			redis = Redis.new
			redis.psubscribe("#{@prefix}.#{MULTI}:#{multi}.#{type}:#{pin}.value") do |on|
				on.pmessage do |pattern, channel, value|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ].symbolize_keys
					yield parse[:multiplexer].to_i, parse[type].to_i, value.to_f
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
		profile = get_profile(:sensor, get_config(:sensor, multi_id, sensor)[:profile])
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
		Thread.new{
			redis = Redis.new :host => @host, :port => @port
			redis.psubscribe("#{@prefix}.#{MULTI}:*.#{SENS}:*.#{CONF}") do |on|
				on.pmessage do |pattern, channel, message|
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ].symbolize_keys
					parse.merge!(JSON.s_parse(message))
					profile = get_profile :sensor, parse[:profile]
					parse = {pin: profile[:pin], period: profile[:period]}.merge parse #default values
					block.call(parse[:multiplexer], parse[:sensor], profile[:function], parse[:period], *[profile[:option1], profile[:option2]])
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
					parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ].symbolize_keys
					yield parse[:multiplexer].to_i, parse[:sensor].to_i
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

