# Contain some extensions to string, hash and json
#

# Modifications to standard class String
#

class String
	# @return True if the string contain something like an integer
	#
	def is_integer?
		begin Integer(self) ; true end rescue false
	end
	
	# @return True if the string contain something like a float
	def is_numeric?
		begin Float(self) ; true end rescue false
	end
		
	# Basic analyse of a String to know if it looks like a rpn
	#
	def is_a_rpn?
		self.split(" ").each do |e|
			return false unless (e.is_numeric? or ["+", "-", "*", "/", "X"].include? e)
		end
		return true
	end
end

# Modifications to standard class Hash
#
class Hash
	# Taken from rails source
	# Return a new hash with all keys converted to symbols.
	#
	def symbolize_keys
		inject({}) do |options, (key, value)|
			options[(key.to_sym rescue key) || key] = value
			options
		end
	end
	
	# Taken from rails source
	# Destructively convert all keys to symbols.
	#
	def symbolize_keys!
		self.replace(self.symbolize_keys)
	end
	
	# Destructively convert all keys to integer
	#
	def integerize_keys!
		self.keys.each do |key|
			self[key.to_i] = self[key]
			self.delete key
		end
		self
	end

	# Destructively recursively convert all keys to symbol
	#
	def recursive_symbolize_keys!
		symbolize_keys!
		# symbolize each hash in .values
		values.each{|h| h.recursive_symbolize_keys! if h.is_a?(Hash) }
		# symbolize each hash inside an array in .values
		values.select{|v| v.is_a?(Array) }.flatten.each{|h| h.recursive_symbolize_keys! if h.is_a?(Hash) }
		self
	end
	
	# Check hash with many options
	# @example Basic usage
	#   hash.must_have(value_a: Integer, value_b: Integer)
	# @example More advanced usage
	#   hash.must_have(odd_number: :odd?, correct_sentence_option: [:end_with?, '.'])
	# @example Even more advanced usage
	#   hash.must_have(value_a: ->(v){v.is_a? Integer or v.is_a? String})
	# @example You can define your own error message, or return nil if allright
	#   hash.must_have(odd_number: ->(v){v.odd? ? nil : "odd_number MUST BE ODD"})
	# @raise ArgumentError if an option is missing
	#
	def must_have(obligatory)
		errors = []
		obligatory.each do |argument, check|
			check, *args = check
			errors << "#{argument} is missing" unless self[argument]
			result = check_option(argument, check, *args) if self[argument]
			errors << result unless result == nil
		end
		raise ArgumentError, errors.join(", ") unless errors.empty?
	end
	
	# @see Hash#must_have
	# Same behavior as Hash#must_have but will not raise exception if a value is missing
	# You can also define default value that will be set if the option is not set (but it will still raise an error if it has bad type)
	# @example With and without default value. Note that if more than 2 elements are in the array, the last one will always be default argument (TODO : fix this...)
	#   hash.can_have(a: Integer, b: [String, "default value"], c: [:odd?, 1])
	#
	def can_have(optional)
		errors = []
		optional.each do |argument, checkdefault|
			check, *args, default = checkdefault
			result = check_option(argument, check, *args) if self[argument]
			errors << result unless result == nil
			self[argument] = self[argument] || default if default
		end
		raise ArgumentError, errors.join(", ") unless errors.empty?
	end
	
	private
	
	# Common part of can_have and must_have methods
	#
	def check_option(argname, check, *args)
		result = true
		argument = self[argname]
		if check.is_a? Class and not argument.is_a?(check)
			result = "should be #{check}"
		elsif (check.is_a? Symbol)
			if argument.respond_to?(check, true)# and ((argument.method(check).arity == args.size) or argument.method(check).arity) TODO deal with arity
				result = argument.method(check).call(*args)
			elsif Object.respond_to?(check, true)# and Object.method(check).arity == args.size + 1
				result = Object.method(check).call(argument, *args)
			else
				result = "it has a bad type"
			end
		elsif (check.is_a? Proc or check.is_a? Method)
			result = check.call(argument)
		end
		return "#{argname} is wrong : #{result}" if result.is_a? String
		return "#{argname} is invalid" if result == false
		return nil
	end
end


# Modification to JSON library
#
module JSON
	class << self
		# Parse and symbolize keys of the result
		#
		def s_parse(source, opts = {})
			result = Parser.new(source, opts).parse
			result.recursive_symbolize_keys! if result.is_a? Hash
		end
	end
end

