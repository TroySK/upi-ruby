# frozen_string_literal: true

require_relative "upi/version"
require_relative "upi/errors"
require_relative "upi/configuration"
require_relative "upi/utils/crypto"
require_relative "upi/utils/currency"
require_relative "upi/utils/validation"
require_relative "upi/utils/validation_requests"
require_relative "upi/utils/sanitize"
require_relative "upi/utils/retry"
require_relative "upi/utils/logger"
require_relative "upi/utils/ip_guard"
require_relative "upi/qr"
require_relative "upi/adapters/base"
require_relative "upi/adapters/phonepe"
require_relative "upi/adapters/paytm"
require_relative "upi/client"

module UPI
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
      configuration.apply_env_defaults!
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def client(overrides = {})
      Client.from_config(merged_config(overrides))
    end

    private

    def merged_config(overrides)
      base = configuration
      pick = lambda do |key|
        if overrides.key?(key)
          # Explicit nil clears the global value so ENV can refill it;
          # explicit false/0 are real values and must be kept.
          val = overrides[key]
          val.nil? ? nil : val
        elsif overrides.key?(key.to_s)
          val = overrides[key.to_s]
          val.nil? ? nil : val
        else
          base.public_send(key)
        end
      end
      attrs = {
        provider: pick.call(:provider),
        environment: pick.call(:environment),
        credentials: pick.call(:credentials),
        merchant_id: pick.call(:merchant_id),
        salt_key: pick.call(:salt_key),
        salt_index: pick.call(:salt_index),
        merchant_key: pick.call(:merchant_key),
        website: pick.call(:website),
        timeout: pick.call(:timeout),
        debug: pick.call(:debug),
        logger: pick.call(:logger),
        callback_url: pick.call(:callback_url),
        redirect_url: pick.call(:redirect_url),
        max_retries: pick.call(:max_retries),
        retry_delay_ms: pick.call(:retry_delay_ms)
      }
      Configuration.new(attrs)
    end
  end
end

begin
  require "rails/engine"
  require_relative "upi/engine"
rescue LoadError
  nil
end
