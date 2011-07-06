require './redis-interface.rb'

cli = Redis_interface.new(1, 'localhost', 6379)
cli.on_published_value(:sensor) do |multi, pin, value|
	puts "The multiplexor #{multi} published on pin #{pin} the value #{value}"
end

sleep

