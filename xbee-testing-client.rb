require './redis-interface.rb'

cli = Redis_interface.new(1, 'localhost', 6379)
Thread.abort_on_exception = true
cli.on_published_value(:sensor) do |multi, pin, value|
	profile = cli.list_profiles[cli.get_sensor_config(multi, pin)["profile"]]
	puts "The multiplexor #{multi} published on pin #{pin} the value #{value.round(2)}#{profile["unit"]}"
end

sleep

