# frozen_string_literal: true

module UPI
  # POST /upi/webhooks/:provider  — verifies PSP callbacks.
  # Mount via: mount UPI::Engine => "/upi"
  class WebhooksController < ActionController::Base
    skip_before_action :verify_authenticity_token, raise: false

    def create
      provider = params[:provider].to_s.downcase
      unless %w[phonepe paytm].include?(provider)
        render json: { error: "Unknown provider: #{provider}", code: "INVALID_CONFIG" }, status: :bad_request
        return
      end
      raw_body = request.raw_post
      if raw_body.nil? || raw_body.empty?
        render json: { error: "Empty webhook body", code: "WEBHOOK_VERIFICATION_FAILED" }, status: :bad_request
        return
      end
      headers = request.headers
      signature = headers["X-VERIFY"] || headers["X-Verify"] || headers["x-verify"] ||
                  params["CHECKSUMHASH"] || params["CHECKSUM"] ||
                  params["checksum"] || params["checkSum"] || ""
      client = UPI.client(provider: provider)
      expected = params[:expected_amount].to_s.strip
      expected = expected.empty? ? nil : Integer(expected)
      event = client.verify_webhook(raw_body, signature.to_s,
        expected_amount: expected,
        enable_replay_protection: truthy_param?(params[:replay_protection]))
      if event[:verified]
        head :ok
      else
        head :unauthorized
      end
    rescue ArgumentError
      render json: { error: "expected_amount must be an integer (paise)", code: "INVALID_CONFIG" }, status: :bad_request
    rescue UPI::Error => e
      render json: { error: e.message, code: e.code }, status: :bad_request
    end

    private

    def truthy_param?(value)
      return false if value.nil? || value == false
      return true if value == true
      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end
  end
end
