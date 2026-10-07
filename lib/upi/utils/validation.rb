# frozen_string_literal: true

module UPI
  module Utils
    # Input validation.
    module Validation
      VALID_PROVIDERS = %w[phonepe paytm].freeze
      REQUIRED_CREDENTIALS = {
        "phonepe" => %w[merchantId saltKey saltIndex],
        "paytm" => %w[merchantId merchantKey]
      }.freeze
      PLACEHOLDER_PATTERN = /\A(your[-_]|test[-_]|xxx|placeholder|change[-_]me|TODO|FIXME)/i
      DANGEROUS_SCHEMES = /\A(javascript|data|vbscript|file):/i
      ALLOWED_URL_SCHEMES = /\A(https?|upi):\/\//i
      MIN_AMOUNT_PAISE = 100
      MAX_AMOUNT_PAISE = 100_000_000
      ORDER_ID_PATTERN = /\A[a-zA-Z0-9_\-\.]{1,128}\z/
      SALT_INDEX_PATTERN = /\A\d{1,4}\z/
      VPA_PATTERN = /\A[a-zA-Z0-9.\-_]+@[a-zA-Z0-9]+\z/

      module_function

      def validate_config(provider:, environment:, credentials:, timeout: nil)
        unless VALID_PROVIDERS.include?(provider.to_s)
          raise InvalidConfigError, "Invalid provider. Must be: phonepe, paytm"
        end
        unless %w[sandbox production].include?(environment.to_s)
          raise InvalidConfigError, "Invalid environment. Must be: sandbox, production"
        end
        unless credentials.is_a?(Hash)
          raise InvalidConfigError.new("credentials is required", provider.to_s)
        end
        REQUIRED_CREDENTIALS[provider.to_s].each do |key|
          val = credentials[key] || credentials[key.to_sym]
          # Coerce numeric saltIndex (e.g. 1) to string; reject other non-strings.
          val = val.to_s if key == "saltIndex" && val.is_a?(Numeric)
          if val.nil? || !val.is_a?(String) || val.strip.empty?
            raise InvalidConfigError.new("Missing credential #{key} for #{provider}", provider.to_s)
          end
          if PLACEHOLDER_PATTERN.match?(val)
            raise InvalidConfigError.new("Credential #{key} looks like a placeholder.", provider.to_s)
          end
        end
        if provider.to_s == "paytm"
          key = credentials["merchantKey"] || credentials[:merchantKey]
          if key.is_a?(String) && key.length < 16
            raise InvalidConfigError.new("Paytm merchantKey must be >= 16 chars.", "paytm")
          end
        end
        if provider.to_s == "phonepe"
          salt = credentials["saltIndex"] || credentials[:saltIndex]
          validate_salt_index(salt.to_s) if salt.is_a?(String)
        end
        unless timeout.nil?
          unless timeout.is_a?(Numeric) && timeout >= 1000 && timeout <= 120_000
            raise InvalidConfigError, "timeout must be between 1000ms and 120000ms"
          end
        end
        true
      end

      def validate_order_id(order_id)
        raise InvalidConfigError, "orderId is required" if order_id.nil? || order_id.to_s.strip.empty?
        unless ORDER_ID_PATTERN.match?(order_id.to_s)
          raise InvalidConfigError, "orderId must be 1-128 chars, alphanumeric with hyphens/underscores/dots only"
        end
        true
      end

      def validate_salt_index(salt_index)
        unless SALT_INDEX_PATTERN.match?(salt_index.to_s.strip)
          raise InvalidConfigError, 'saltIndex must be a numeric string (e.g., "1")'
        end
        true
      end

      def normalize_phone_number(phone)
        digits = phone.to_s.gsub(/\D/, "")
        # Strip trunk/STD prefixes first: 091 + 10 digits, or 0 + 10 digits.
        return digits[3..] if digits.length == 13 && digits.start_with?("091")
        return digits[1..] if digits.length == 11 && digits.start_with?("0")
        # Strip 91 country code only when it leaves a valid 10-digit mobile.
        if digits.length == 12 && digits.start_with?("91") && digits[2..] =~ /\A[6-9]\d{9}\z/
          return digits[2..]
        end
        digits
      end

      def validate_url(url, field_name, env)
        trimmed = url.to_s.strip
        if trimmed.empty?
          raise InvalidConfigError, "#{field_name} is required"
        end
        if DANGEROUS_SCHEMES.match?(trimmed)
          raise InvalidConfigError, "#{field_name} contains a dangerous URL scheme."
        end
        unless ALLOWED_URL_SCHEMES.match?(trimmed)
          raise InvalidConfigError, "#{field_name} must be a valid http(s) URL"
        end
        if env.to_s == "production" && !trimmed.start_with?("https://")
          raise InvalidConfigError, "#{field_name} must use HTTPS in production"
        end
        true
      end
    end
  end
end
