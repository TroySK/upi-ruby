# frozen_string_literal: true

module UPI
  module Utils
    module Validation
      module_function

      def validate_payment_request(req, env)
        amount = req[:amount] || req["amount"]
        unless amount.is_a?(Integer) && amount.positive?
          raise InvalidConfigError, "amount must be a positive integer (paise). For Rs 500, use 50000"
        end
        raise InvalidConfigError, "amount must be at least 100 paise" if amount < MIN_AMOUNT_PAISE
        raise InvalidConfigError, "amount exceeds maximum" if amount > MAX_AMOUNT_PAISE
        validate_order_id(req[:order_id] || req[:orderId] || req["order_id"] || req["orderId"])
        raw_phone = req[:customer_phone] || req[:customerPhone] || req["customer_phone"] || req["customerPhone"] || ""
        normalized = normalize_phone_number(raw_phone)
        unless normalized.match?(/\A[6-9]\d{9}\z/)
          raise InvalidConfigError, "customerPhone must be a valid 10-digit Indian mobile number"
        end
        callback = req[:callback_url] || req[:callbackUrl] || req["callback_url"] || req["callbackUrl"]
        redirect = req[:redirect_url] || req[:redirectUrl] || req["redirect_url"] || req["redirectUrl"]
        raise InvalidConfigError, "callbackUrl is required" if callback.nil? || callback.to_s.strip.empty?
        raise InvalidConfigError, "redirectUrl is required" if redirect.nil? || redirect.to_s.strip.empty?
        validate_url(callback.to_s, "callbackUrl", env)
        validate_url(redirect.to_s, "redirectUrl", env)
        email = req[:customer_email] || req[:customerEmail] || req["customer_email"] || req["customerEmail"]
        if !email.nil? && !email.to_s.strip.empty? && !email.to_s.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
          raise InvalidConfigError, "customerEmail is not a valid email address"
        end
        true
      end

      def validate_qr_request(req)
        vpa = req[:vpa] || req["vpa"]
        name = req[:name] || req["name"]
        amount = req[:amount] || req["amount"]
        order_id = req[:order_id] || req[:orderId] || req["order_id"] || req["orderId"]
        note = req[:note] || req["note"]
        vpa_str = vpa.to_s
        raise InvalidConfigError, "vpa must be a valid UPI VPA" if vpa.nil? || !vpa_str.include?("@")
        raise InvalidConfigError, "vpa format is invalid" unless VPA_PATTERN.match?(vpa_str)
        raise InvalidConfigError, "name is required" if name.nil? || name.to_s.strip.empty?
        raise InvalidConfigError, "name must be 100 chars or less" if name.to_s.length > 100
        raise InvalidConfigError, "amount must be positive rupees" if amount.nil? || !amount.is_a?(Numeric) || amount <= 0
        raise InvalidConfigError, "amount exceeds maximum" if amount > MAX_AMOUNT_PAISE / 100
        raise InvalidConfigError, "orderId is required" if order_id.nil? || order_id.to_s.strip.empty?
        validate_order_id(order_id.to_s)
        raise InvalidConfigError, "note must be 255 chars or less" if note && note.to_s.length > 255
        true
      end
    end
  end
end
