# frozen_string_literal: true

require "base64"
require "json"

module UPI
  module Adapters
    # Shared adapter behaviour.
    module Base
      def check_status(order_id, options = {})
        UPI::Utils::Validation.validate_order_id(order_id.to_s)
        max = opt_value(options, :max_retries, @config_max_retries, 3)
        delay = opt_value(options, :retry_delay_ms, @config_retry_delay, 1000)
        UPI::Utils::Retry.with_retry(max_attempts: max, base_delay_ms: delay) do
          fetch_status(order_id, options)
        end
      end

      private

      # Option lookup that accepts :snake, "snake", :camel, and "camel".
      # max_attempts=0 means "no retries" and must not fall through to the default.
      def opt_value(options, snake, configured, default)
        options ||= {}
        camel = snake.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
        camel_str = camel.to_s
        snake_str = snake.to_s
        val = if options.key?(snake)
                options[snake]
              elsif options.key?(snake_str)
                options[snake_str]
              elsif options.key?(camel)
                options[camel]
              elsif options.key?(camel_str)
                options[camel_str]
              else
                configured.nil? ? default : configured
              end
        val.nil? ? default : val
      end

      # Credential lookup that accepts "camel", :camel, "snake", and :snake.
      # `false` is a real value; only nil falls through to the next key.
      def cred_lookup(credentials, *keys)
        creds = credentials || {}
        keys.each do |k|
          next if k.nil?
          return creds[k] if creds.key?(k)
          str = k.to_s
          return creds[str] if creds.key?(str)
          sym = str.to_sym
          return creds[sym] if creds.key?(sym)
        end
        nil
      end

      # Unified request-field lookup across :snake, "snake", :camel, "camel".
      def req_value(request, snake)
        request ||= {}
        camel = snake.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
        [snake, snake.to_s, camel, camel.to_s].each do |k|
          return request[k] if request.key?(k)
        end
        sym_snake = snake.to_sym
        [sym_snake, sym_snake.to_s].each do |k|
          return request[k] if request.key?(k)
        end
        nil
      end

      # Replay flags often arrive as "1"/"true"/"0" strings (controller params).
      # Only truthy values ("1", "true", "yes", "on", true) enable protection —
      # "false"/"0"/"" must NOT enable it.
      def truthy_opt?(options, snake)
        val = opt_value(options, snake, nil, nil)
        return false if val.nil? || val == false
        return true if val == true
        %w[1 true yes on].include?(val.to_s.strip.downcase)
      end
    end
  end
end
