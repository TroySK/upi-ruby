# frozen_string_literal: true

require_relative "lib/upi/version"

Gem::Specification.new do |spec|
  spec.name = "upi"
  spec.version = UPI::VERSION
  spec.authors = ["Troy SK"]
  spec.email = ["shirsendu.karmakar@gmail.com"]

  spec.summary = "Free zero-commission UPI payments for Ruby & Rails"
  spec.description = "Accept UPI payments in Ruby for free. Zero commission. " \
    "PhonePe Business & Paytm Business adapters, UPI QR generation, " \
    "webhook verification, refunds. Rails Engine included."
  spec.homepage = "https://github.com/troysk/upi-ruby"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*", "app/**/*", "config/**/*", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Runtime deps — kept minimal & pluggable.
  # railties is optional: only needed for the Rails Engine / webhook controller.
  spec.add_dependency "faraday", ">= 2.0", "< 3.0"
  spec.add_dependency "rqrcode", ">= 2.0", "< 4.0"
  spec.add_dependency "chunky_png", "~> 1.4"

  spec.add_development_dependency "railties", ">= 6.0"
  spec.add_development_dependency "test-unit", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md"
  }
end
