
# frozen_string_literal: true

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fgt_rest_api/version'

Gem::Specification.new do |spec|
  spec.name          = 'fgt_rest_api'
  spec.version       = FgtRestApi::VERSION
  spec.licenses      = ['Artistic-2.0']
  spec.authors       = ['Stefan Feurle']
  spec.email         = ['stefan.feurle@gmail.com']
  spec.summary       = "ruby API wrapper for accessing FortiNet's FortiGate REST API."
  spec.description   = ''
  spec.homepage      = 'https://github.com/fuegito/fgt_rest_api'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'httpclient'
  spec.add_runtime_dependency 'netaddr'

  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'rake', '~> 13.0'
end
