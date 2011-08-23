Gem::Specification.new do |gem|
	gem.name = "sense"
	gem.version = "0.2.1"
	gem.summary = "Manage a sensors network"
	gem.require_paths = ["lib"]
	gem.files = Dir["{lib}/**/*.rb", "{bin}/*","{doc}/**/*", "{arduino}/**/*", "*.md"]
	gem.bindir = 'bin'
	gem.authors = ["plule"]
end

