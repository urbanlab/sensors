require './redis-interface.rb'

cli = Redis_interface.new(1, 'localhost', 6379)
Thread.abort_on_exception = true
cli.on_published_value(:sensor) do |multi, pin, value|
	profile = cli.list_profiles(:sensor)[cli.get_config(:sensor, multi, pin)["profile"]]
	s = "The multiplexor #{multi} published on pin #{pin} "
	s << case profile["unit"]
		when "boolean" then (value == 1)? "on" : "off"
		else "the value #{value.round(2)}#{profile["unit"]}"
	end
	puts s
end

sleep

