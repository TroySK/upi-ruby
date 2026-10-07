# frozen_string_literal: true

require "json"
require "faraday"

module UPI
  module Adapters
    # Paytm Business adapter.
    class Paytm
      include Base

      BASE_URLS = {
        "sandbox" => "https://securestage.paytmpayments.com",
        "production" => "https://secure.paytmpayments.com"
      }.freeze

      attr_reader :provider

      def initialize(credentials, environment, timeout: 30_000, debug: false,
                     logger: nil, max_retries: nil, retry_delay_ms: nil)
        @credentials = {
          "merchantId" => cred_lookup(credentials, "merchantId", :merchantId),
          "merchantKey" => cred_lookup(credentials, "merchantKey", :merchantKey),
          "website" => cred_lookup(credentials, "website", :website)
        }
        @environment = environment.to_s
        @base_url = BASE_URLS[@environment]
        raise UPI::InvalidConfigError, "Invalid environment. Must be: sandbox, production" if @base_url.nil?
        @timeout = timeout.nil? ? 30_000 : timeout.to_i
        @logger = UPI::Utils::Logger.new(debug: debug, logger: logger)
        @config_max_retries = max_retries
        @config_retry_delay = retry_delay_ms
        @provider = "paytm"
        @conn = Faraday.new(url: @base_url) do |f|
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
          f.options.timeout = @timeout / 1000.0
          f.options.open_timeout = [@timeout / 1000.0, 10.0].min
        end
      end

      def website
        site = @credentials["website"]
        return site unless site.nil? || site.to_s.strip.empty?

        @environment == "production" ? "DEFAULT" : "WEBSTAGING"
      end

      def create_payment(request)
        request ||= {}
        phone = UPI::Utils::Validation.normalize_phone_number(req_value(request, :customer_phone))
        order_id = req_value(request, :order_id)
        amount = req_value(request, :amount)
        if order_id.nil? || amount.nil?
          raise UPI::InvalidConfigError, "create_payment requires amount and order_id"
        end
        begin
          int_amount = Integer(amount)
        rescue ArgumentError, TypeError
          raise UPI::InvalidConfigError, "amount must be a positive integer (paise)"
        end
        amount_rs = format("%.2f", int_amount / 100.0)
        body = {
          requestType: "Payment",
          mid: @credentials["merchantId"],
          websiteName: website,
          orderId: order_id,
          callbackUrl: req_value(request, :callback_url),
          txnAmount: { value: amount_rs, currency: "INR" },
          userInfo: { custId: "CUST_#{phone}", mobile: phone }
        }
        params_str = UPI::Utils::Crypto.paytm_params_string(stringify(body))
        sig = UPI::Utils::Crypto.generate_paytm_checksum(params_str, @credentials["merchantKey"])
        begin
          res = @conn.post("/theia/api/v1/initiateTransaction",
            { body: body, head: { signature: sig } })
          unless res.success?
            raise UPI::PaymentError.new("Paytm API error (#{res.status})",
              provider: "paytm", retriable: res.status >= 500)
          end
          payload = res.body.is_a?(Hash) ? res.body : {}
          token = payload.dig("body", "txnToken") || ""
          require "uri"
          url = "#{@base_url}/theia/showPaymentPage?#{URI.encode_www_form(mid: @credentials["merchantId"], orderId: order_id)}"
          { success: true, payment_url: url, order_id: order_id,
            provider_transaction_id: token, raw_response: payload }
        rescue UPI::PaymentError
          raise
        rescue StandardError => e
          raise wrap_error(e, "Failed to create payment")
        end
      end
      def fetch_status(order_id, options = {})
        body = { mid: @credentials["merchantId"], orderId: order_id }
        params_str = UPI::Utils::Crypto.paytm_params_string(stringify(body))
        sig = UPI::Utils::Crypto.generate_paytm_checksum(params_str, @credentials["merchantKey"])
        begin
          res = @conn.post("/v3/order/status", { body: body, head: { signature: sig } })
          unless res.success?
            raise UPI::PaymentError.new("Paytm status error (#{res.status})",
              provider: "paytm", retriable: res.status >= 500)
          end
          payload = res.body.is_a?(Hash) ? res.body : {}
          raw_info = payload.dig("body", "resultInfo")
          info = raw_info.is_a?(Hash) ? raw_info : {}
          pbody = payload["body"].is_a?(Hash) ? payload["body"] : {}
          amount = (pbody["txnAmount"].to_s.to_f * 100).round
          expected = opt_value(options, :expected_amount, nil, nil)
          if !expected.nil? && expected.to_i != amount
            raise UPI::PaymentError.new("Amount mismatch", provider: "paytm")
          end
          status = map_status(info["resultStatus"] || pbody["status"])
          { success: status == "SUCCESS", status: status,
            amount: amount, order_id: pbody["orderId"] || order_id,
            transaction_id: pbody["txnId"], payment_method: map_method(pbody["paymentMode"]),
            raw_response: payload }
        rescue UPI::PaymentError
          raise
        rescue StandardError => e
          raise wrap_error(e, "Failed to check payment status")
        end
      end

      def verify_webhook(payload, signature, options = {})
        options ||= {}
        data =
          if payload.is_a?(Hash)
            payload.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
          else
            str = payload.is_a?(String) ? payload : payload.to_s
            begin
              parsed = JSON.parse(str)
            rescue JSON::ParserError
              return { verified: false, status: "FAILED", order_id: "", raw_payload: payload }
            end
            unless parsed.is_a?(Hash)
              return { verified: false, status: "FAILED", order_id: "", raw_payload: payload }
            end
            parsed.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
          end
        checksum =
          if signature.is_a?(String) && !signature.strip.empty?
            signature.strip
          else
            sig = data["CHECKSUMHASH"] || data["CHECKSUM"] || data["checksum"] || data["checkSum"]
            sig.is_a?(String) && !sig.strip.empty? ? sig.strip : nil
          end
        unless checksum.is_a?(String) && !checksum.empty?
          return { verified: false, status: "FAILED", order_id: (data["ORDERID"] || ""), raw_payload: payload }
        end
        params = data.reject { |k, _| %w[CHECKSUMHASH CHECKSUM checksum checkSum CHECKSUM_HASH].include?(k.to_s) }
        params_str = UPI::Utils::Crypto.paytm_params_string(stringify(params))
        valid = UPI::Utils::Crypto.verify_paytm_checksum(params_str, @credentials["merchantKey"], checksum)
        unless valid
          return { verified: false, status: "FAILED", order_id: (data["ORDERID"] || ""), raw_payload: payload }
        end
        if truthy_opt?(options, :enable_replay_protection)
          ts = opt_value(options, :timestamp, nil, nil) || data["TXNDATE"]
          tol = opt_value(options, :timestamp_tolerance_seconds, nil, 300) || 300
          unless ts && UPI::Utils::Crypto.timestamp_fresh?(ts, tol)
            return { verified: false, status: "FAILED", order_id: (data["ORDERID"] || ""), raw_payload: payload }
          end
        end
        amount = data["TXNAMOUNT"] ? (data["TXNAMOUNT"].to_s.to_f * 100).round : nil
        expected = opt_value(options, :expected_amount, nil, nil)
        if !expected.nil? && !amount.nil? && expected.to_i != amount
          return { verified: false, status: map_status(data["STATUS"]), order_id: (data["ORDERID"] || ""),
                   transaction_id: data["TXNID"], amount: amount, raw_payload: payload }
        end
        { verified: true, status: map_status(data["STATUS"]), order_id: (data["ORDERID"] || ""),
          transaction_id: data["TXNID"], amount: amount, raw_payload: payload }
      end

      def create_refund(request)
        request ||= {}
        order_id = req_value(request, :original_order_id) || req_value(request, :order_id)
        refund_id = req_value(request, :refund_id)
        amount = req_value(request, :amount)
        txn_id = req_value(request, :provider_transaction_id)
        if order_id.nil? || order_id.to_s.strip.empty? ||
           refund_id.nil? || refund_id.to_s.strip.empty? || amount.nil? ||
           txn_id.nil? || txn_id.to_s.strip.empty?
          raise UPI::InvalidConfigError, "create_refund requires original_order_id, refund_id, amount, and provider_transaction_id"
        end
        begin
          int_amount = Integer(amount)
        rescue ArgumentError, TypeError
          raise UPI::InvalidConfigError, "refund amount must be a positive integer (paise)"
        end
        raise UPI::InvalidConfigError, "refund amount must be a positive integer (paise)" unless int_amount.positive?
        body = { mid: @credentials["merchantId"], orderId: order_id, txnId: txn_id,
                 refundId: refund_id, txnAmount: format("%.2f", int_amount / 100.0) }
        params_str = UPI::Utils::Crypto.paytm_params_string(stringify(body))
        sig = UPI::Utils::Crypto.generate_paytm_checksum(params_str, @credentials["merchantKey"])
        begin
          res = @conn.post("/v3/order/refund", { body: body, head: { signature: sig } })
          unless res.success?
            raise UPI::RefundError.new("Paytm refund error (#{res.status})",
              provider: "paytm", retriable: res.status >= 500)
          end
          payload = res.body.is_a?(Hash) ? res.body : {}
          raw_info = payload.dig("body", "resultInfo")
          info = raw_info.is_a?(Hash) ? raw_info : {}
          status = map_refund_status(info["resultStatus"])
          { success: status == "SUCCESS", status: status, refund_id: refund_id,
            original_order_id: order_id, amount: int_amount,
            provider_refund_id: payload.dig("body", "refundId"), raw_response: payload }
        rescue UPI::RefundError
          raise
        rescue StandardError => e
          raise UPI::RefundError.new("Failed to initiate refund: #{e.message}", provider: "paytm", cause: e)
        end
      end

      private

      def stringify(obj)
        case obj
        when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify(v) }
        when Array then obj.map { |v| stringify(v) }
        else obj
        end
      end

      def map_status(status)
        case status.to_s
        when "TXN_SUCCESS", "S" then "SUCCESS"
        when "TXN_FAILURE", "F" then "FAILED"
        when "PENDING" then "PENDING"
        else "PENDING"
        end
      end

      def map_refund_status(status)
        case status.to_s
        when "TXN_SUCCESS", "S" then "SUCCESS"
        when "TXN_FAILURE", "F" then "FAILED"
        else "PENDING"
        end
      end

      def map_method(mode)
        return "upi" if mode.to_s.upcase == "UPI"
        return "wallet" if %w[PPI PAYTM].include?(mode.to_s.upcase)
        "unknown"
      end

      def wrap_error(error, message)
        msg = error.message.to_s
        if msg.match?(/ECONNREFUSED|ETIMEDOUT|Timeout|connection/i) ||
           error.is_a?(Faraday::TimeoutError) || error.is_a?(Faraday::ConnectionFailed)
          UPI::NetworkError.new("#{message}: #{msg}", provider: "paytm", cause: error)
        else
          UPI::PaymentError.new("#{message}: #{msg}", provider: "paytm", cause: error)
        end
      end
    end
  end
end
