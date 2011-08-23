require 'sense/client'

host = ARGV[0] || 'localhost'
cli = Sense::Client.new(2, host, 6379)
Thread.abort_on_exception = true
cli.on_published_value(:sensor) do |multi, pin, value, unit, name|
	s = "#{multi}:#{pin} : #{name} - "
	s << case unit
		when "boolean" then (value == 1)? "on" : "off"
		else "#{value}#{unit}"
	end
	puts s
end

sleep

