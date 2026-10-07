# frozen_string_literal: true

begin
  require "rails/engine"
rescue LoadError
  return
end

module UPI
  # Rails Engine — mounts webhook controllers + helpers.
  #
  #   # config/routes.rb
  #   mount UPI::Engine => "/upi"
  #
  #   # config/initializers/upi.rb
  #   UPI.configure do |c|
  #     c.provider = :phonepe
  #     c.merchant_id = Rails.application.credentials.dig(:upi, :merchant_id)
  #     c.salt_key = Rails.application.credentials.dig(:upi, :salt_key)
  #   end
  class Engine < ::Rails::Engine
    isolate_namespace UPI
    config.generators { |g| g.test_framework :test_unit }
    initializer "upi.configure" do
      UPI.configuration.apply_env_defaults! rescue nil
    end
  end
end
