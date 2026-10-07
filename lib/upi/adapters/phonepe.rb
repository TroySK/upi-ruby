# frozen_string_literal: true

require "base64"
require "json"
require "faraday"

module UPI
  module Adapters
    # PhonePe Business adapter.
    class PhonePe
      include Base

      BASE_URLS = {
        "sandbox" => "https://api-preprod.phonepe.com/apis/pg-sandbox",
        "production" => "https://api.phonepe.com/apis/hermes"
      }.freeze

      attr_reader :provider

      def initialize(credentials, environment, timeout: 30_000, debug: false,
                     logger: nil, max_retries: nil, retry_delay_ms: nil)
        salt = cred_lookup(credentials, "saltIndex", :saltIndex)
        UPI::Utils::Validation.validate_salt_index(salt.nil? ? "1" : salt)
        @credentials = {
          "merchantId" => cred_lookup(credentials, "merchantId", :merchantId),
          "saltKey" => cred_lookup(credentials, "saltKey", :saltKey),
          "saltIndex" => (salt.nil? ? "1" : salt).to_s
        }
        @environment = environment.to_s
        @base_url = BASE_URLS[@environment]
        raise UPI::InvalidConfigError, "Invalid environment. Must be: sandbox, production" if @base_url.nil?
        @timeout = timeout.nil? ? 30_000 : timeout.to_i
        @logger = UPI::Utils::Logger.new(debug: debug, logger: logger)
        @config_max_retries = max_retries
        @config_retry_delay = retry_delay_ms
        @provider = "phonepe"
        @conn = Faraday.new(url: @base_url) do |f|
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
          f.options.timeout = @timeout / 1000.0
          f.options.open_timeout = [@timeout / 1000.0, 10.0].min
        end
      end

      def create_payment(request)
        request ||= {}
        phone = UPI::Utils::Validation.normalize_phone_number(req_value(request, :customer_phone))
        order_id = req_value(request, :order_id)
        amount = req_value(request, :amount)
        if order_id.nil? || amount.nil?
          raise UPI::InvalidConfigError, "create_payment requires amount and order_id"
        end
        payload = {
          merchantId: @credentials["merchantId"],
          merchantTransactionId: order_id,
          merchantUserId: "MUID_#{phone}",
          amount: amount,
          redirectUrl: req_value(request, :redirect_url),
          redirectMode: "REDIRECT",
          callbackUrl: req_value(request, :callback_url),
          paymentInstrument: { type: "PAY_PAGE" }
        }
        b64 = Base64.strict_encode64(JSON.generate(payload))
        checksum = generate_checksum(b64, "/pg/v1/pay")
        headers = { "X-VERIFY" => checksum }
        idem = req_value(request, :idempotency_key)
        headers["X-IDEMPOTENCY-KEY"] = idem.to_s unless idem.nil? || idem.to_s.empty?
        begin
          res = @conn.post("/pg/v1/pay", { request: b64 }, headers)
          unless res.success?
            raise UPI::PaymentError.new("PhonePe API error (#{res.status})",
              provider: "phonepe", retriable: res.status >= 500)
          end
          body = res.body.is_a?(Hash) ? res.body : {}
          url = body.dig("data", "instrumentResponse", "redirectInfo", "url") || ""
          { success: body["success"], payment_url: url, order_id: order_id,
            provider_transaction_id: body.dig("data", "merchantTransactionId"),
            raw_response: body }
        rescue UPI::PaymentError
          raise
        rescue StandardError => e
          raise wrap_error(e, "Failed to create payment")
        end
      end
      def fetch_status(order_id, options = {})
        path = "/pg/v1/status/#{@credentials["merchantId"]}/#{order_id}"
        checksum = generate_checksum("", path)
        begin
          res = @conn.get(path) do |req|
            req.headers["X-VERIFY"] = checksum
            req.headers["X-MERCHANT-ID"] = @credentials["merchantId"]
          end
          unless res.success?
            raise UPI::PaymentError.new("PhonePe status error (#{res.status})",
              provider: "phonepe", retriable: res.status >= 500)
          end
          body = res.body.is_a?(Hash) ? res.body : {}
          data = body["data"].is_a?(Hash) ? body["data"] : {}
          amount = data["amount"] || 0
          expected = opt_value(options, :expected_amount, nil, nil)
          if !expected.nil? && expected.to_i != amount.to_i
            raise UPI::PaymentError.new("Amount mismatch", provider: "phonepe")
          end
          { success: body["success"], status: map_status(body["code"]),
            amount: amount, order_id: data["merchantTransactionId"] || order_id,
            transaction_id: data["transactionId"],
            payment_method: map_method(data.dig("paymentInstrument", "type")),
            raw_response: body }
        rescue UPI::PaymentError
          raise
        rescue StandardError => e
          raise wrap_error(e, "Failed to check payment status")
        end
      end

      def verify_webhook(payload, signature, options = {})
        options ||= {}
        unless signature.is_a?(String) && !signature.strip.empty?
          return { verified: false, status: "FAILED", order_id: "", raw_payload: payload }
        end
        if signature.strip.length > 512
          return { verified: false, status: "FAILED", order_id: "", raw_payload: payload }
        end
        str = payload.is_a?(String) ? payload : JSON.generate(payload)
        b64 = str
        begin
          wrapper = JSON.parse(str)
          b64 = wrapper["response"] if wrapper.is_a?(Hash) && wrapper["response"].is_a?(String)
        rescue JSON::ParserError
          nil
        end
        expected = generate_callback_checksum(b64)
        valid = UPI::Utils::Crypto.constant_time_equal(expected, signature.strip)
        unless valid
          return { verified: false, status: "FAILED", order_id: "", raw_payload: payload }
        end
        parsed = nil
        begin
          parsed = JSON.parse(Base64.decode64(b64))
        rescue StandardError
          begin
            parsed = JSON.parse(b64)
          rescue StandardError
            nil
          end
        end
        if truthy_opt?(options, :enable_replay_protection)
          ts = opt_value(options, :timestamp, nil, nil) ||
               (parsed && (parsed["timestamp"] || (parsed["data"].is_a?(Hash) ? parsed.dig("data", "timestamp") : nil)))
          tol = opt_value(options, :timestamp_tolerance_seconds, nil, 300) || 300
          unless ts && UPI::Utils::Crypto.timestamp_fresh?(ts, tol)
            return { verified: false, status: "FAILED",
                     order_id: parsed.is_a?(Hash) ? (parsed.dig("data", "merchantTransactionId") || "") : "", raw_payload: payload }
          end
        end
        data = parsed.is_a?(Hash) && parsed["data"].is_a?(Hash) ? parsed["data"] : {}
        order_id = data["merchantTransactionId"] || ""
        expected_amount = opt_value(options, :expected_amount, nil, nil)
        if !expected_amount.nil? && data["amount"] && expected_amount.to_i != data["amount"].to_i
          return { verified: false, status: map_status(parsed.is_a?(Hash) ? parsed["code"] : nil),
                   order_id: order_id, transaction_id: data["transactionId"],
                   amount: data["amount"], raw_payload: payload }
        end
        { verified: true, status: map_status(parsed.is_a?(Hash) ? parsed["code"] : nil), order_id: order_id,
          transaction_id: data["transactionId"], amount: data["amount"], raw_payload: payload }
      end
      def create_refund(request)
        request ||= {}
        order_id = req_value(request, :original_order_id) || req_value(request, :order_id)
        refund_id = req_value(request, :refund_id)
        amount = req_value(request, :amount)
        if order_id.nil? || order_id.to_s.strip.empty? ||
           refund_id.nil? || refund_id.to_s.strip.empty? || amount.nil?
          raise UPI::InvalidConfigError, "create_refund requires original_order_id, refund_id, and amount"
        end
        begin
          int_amount = Integer(amount)
        rescue ArgumentError, TypeError
          raise UPI::InvalidConfigError, "refund amount must be a positive integer (paise)"
        end
        raise UPI::InvalidConfigError, "refund amount must be a positive integer (paise)" unless int_amount.positive?
        payload = { merchantId: @credentials["merchantId"], merchantTransactionId: order_id,
                    merchantRefundId: refund_id, amount: int_amount }
        b64 = Base64.strict_encode64(JSON.generate(payload))
        checksum = generate_checksum(b64, "/pg/v1/refund")
        begin
          res = @conn.post("/pg/v1/refund", { request: b64 }, { "X-VERIFY" => checksum })
          unless res.success?
            raise UPI::RefundError.new("PhonePe refund error (#{res.status})",
              provider: "phonepe", retriable: res.status >= 500)
          end
          body = res.body.is_a?(Hash) ? res.body : {}
          { success: body["success"], status: map_refund_status(body["code"]),
            refund_id: refund_id, original_order_id: order_id, amount: int_amount,
            provider_refund_id: body.dig("data", "transactionId"), raw_response: body }
        rescue UPI::RefundError
          raise
        rescue StandardError => e
          raise UPI::RefundError.new("Failed to initiate refund: #{e.message}", provider: "phonepe", cause: e)
        end
      end

      private

      def generate_checksum(b64, path)
        data = "#{b64}#{path}#{@credentials["saltKey"]}"
        UPI::Utils::Crypto.sha256(data) + "###" + @credentials["saltIndex"]
      end

      def generate_callback_checksum(response)
        data = "#{response}#{@credentials["saltKey"]}"
        UPI::Utils::Crypto.sha256(data) + "###" + @credentials["saltIndex"]
      end

      def map_status(code)
        case code
        when "PAYMENT_SUCCESS" then "SUCCESS"
        when "PAYMENT_ERROR", "PAYMENT_CANCELLED", "PAYMENT_DECLINED",
             "TIMED_OUT", "USER_CANCELLED", "BAD_REQUEST" then "FAILED"
        when "PAYMENT_PENDING" then "PENDING"
        else "PENDING"
        end
      end

      def map_refund_status(code)
        case code
        when "PAYMENT_SUCCESS" then "SUCCESS"
        when "PAYMENT_ERROR", "PAYMENT_CANCELLED" then "FAILED"
        else "PENDING"
        end
      end

      def map_method(type)
        return "upi" if type.to_s.upcase == "UPI"
        return "wallet" if type.to_s.upcase == "WALLET"
        "unknown"
      end

      def wrap_error(error, message)
        msg = error.message.to_s
        if msg.match?(/ECONNREFUSED|ETIMEDOUT|Timeout|connection/i) ||
           error.is_a?(Faraday::TimeoutError) || error.is_a?(Faraday::ConnectionFailed)
          UPI::NetworkError.new("#{message}: #{msg}", provider: "phonepe", cause: error)
        else
          UPI::PaymentError.new("#{message}: #{msg}", provider: "phonepe", cause: error)
        end
      end
    end
  end
end
