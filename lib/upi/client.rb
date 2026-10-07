# frozen_string_literal: true

module UPI
  # Unified UPI client.
  #
  #   client = UPI::Client.new(provider: "phonepe", environment: "sandbox",
  #     credentials: { "merchantId" => "...", "saltKey" => "...", "saltIndex" => "1" })
  #   client = UPI::Client.from_env  # reads UPI_* ENV vars
  class Client
    attr_reader :provider, :environment, :adapter

    def initialize(provider:, environment:, credentials:, timeout: 30_000, debug: false,
                   logger: nil, max_retries: nil, retry_delay_ms: nil)
      provider = provider.to_s.downcase
      environment = environment.to_s.downcase
      creds = (credentials || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      timeout = timeout.to_i if timeout.is_a?(String) && timeout.strip.match?(/\A[+-]?\d+\z/)
      debug = coerce_debug(debug)
      UPI::Utils::Validation.validate_config(provider: provider, environment: environment,
        credentials: creds, timeout: timeout)
      @provider = provider
      @environment = environment
      @credentials = creds
      @logger = UPI::Utils::Logger.new(debug: debug, logger: logger)
      @adapter = build_adapter(creds, timeout: timeout, debug: debug, logger: logger,
        max_retries: max_retries, retry_delay_ms: retry_delay_ms)
      @logger.info("UPI initialised -- #{provider} (#{environment}) -- Rs 0 per transaction")
    end

    def self.from_env(overrides = {})
      cfg = UPI::Configuration.from_env(overrides)
      if cfg.provider.nil? || cfg.provider.to_s.strip.empty?
        raise UPI::InvalidConfigError, "UPI_PROVIDER is required (phonepe|paytm)"
      end
      new(provider: cfg.normalized_provider, environment: cfg.normalized_environment,
        credentials: cfg.effective_credentials, timeout: cfg.effective_timeout,
        debug: cfg.debug?, logger: cfg.logger,
        max_retries: cfg.max_retries, retry_delay_ms: cfg.retry_delay_ms)
    end

    def self.from_config(config)
      new(provider: config.normalized_provider, environment: config.normalized_environment,
        credentials: config.effective_credentials, timeout: config.effective_timeout,
        debug: config.debug?, logger: config.logger,
        max_retries: config.max_retries, retry_delay_ms: config.retry_delay_ms)
    end

    def generate_qr(vpa:, name:, amount:, order_id:, **opts)
      UPI::QR.generate_qr(vpa: vpa, name: name, amount: amount, order_id: order_id, **opts)
    end

    def build_upi_link(vpa:, name:, amount:, order_id:, **opts)
      UPI::QR.build_upi_uri(vpa: vpa, name: name, amount: amount, order_id: order_id, **opts)
    end

    def build_intent_links(vpa:, name:, amount:, order_id:, **opts)
      uri = build_upi_link(vpa: vpa, name: name, amount: amount, order_id: order_id, **opts)
      UPI::QR.build_intent_links(uri)
    end

    def create_payment(**request)
      req = normalize_payment_request(request)
      UPI::Utils::Validation.validate_payment_request(req, @environment)
      @adapter.create_payment(req)
    end

    def check_status(order_id, options = {})
      UPI::Utils::Validation.validate_order_id(order_id.to_s)
      @adapter.check_status(order_id.to_s, normalize_keys(options))
    end

    def verify_webhook(payload, signature, options = {})
      @adapter.verify_webhook(payload, signature, normalize_keys(options))
    end

    def create_refund(**request)
      req = normalize_keys(request)
      req = req.each_with_object({}) { |(k, v), h| h[k] = v; h[k.to_s] = v }
      @adapter.create_refund(req)
    end

    def get_adapter
      @adapter
    end

    private

    # Accept "true"/"1"/"yes"/"on" strings for debug so ENV-style values work
    # when passed directly. Anything else follows Ruby truthiness except
    # explicit falsy strings ("false"/"0"/""/"off"/"no" → false).
    def coerce_debug(value)
      return value if value.nil? || value == true || value == false
      return true if value.is_a?(Numeric) && value != 0
      return false if value.is_a?(Numeric)

      str = value.to_s.strip.downcase
      return true if %w[1 true yes on].include?(str)
      return false if %w[0 false no off].include?(str) || str.empty?

      !!value
    end

    def build_adapter(creds, timeout:, debug:, logger:, max_retries:, retry_delay_ms:)
      case @provider
      when "phonepe"
        UPI::Adapters::PhonePe.new(creds, @environment, timeout: timeout, debug: debug,
          logger: logger, max_retries: max_retries, retry_delay_ms: retry_delay_ms)
      when "paytm"
        UPI::Adapters::Paytm.new(creds, @environment, timeout: timeout, debug: debug,
          logger: logger, max_retries: max_retries, retry_delay_ms: retry_delay_ms)
      else
        raise UPI::InvalidConfigError, "Unknown provider: #{@provider}"
      end
    end

    def normalize_payment_request(req)
      h = normalize_keys(req)
      out = {}
      out[:amount] = fetch_key(h, :amount) unless fetch_key(h, :amount).nil?
      out[:order_id] = fetch_key(h, :order_id) unless fetch_key(h, :order_id).nil?
      out[:customer_phone] = fetch_key(h, :customer_phone) unless fetch_key(h, :customer_phone).nil?
      out[:customer_name] = fetch_key(h, :customer_name) unless fetch_key(h, :customer_name).nil?
      out[:customer_email] = fetch_key(h, :customer_email) unless fetch_key(h, :customer_email).nil?
      out[:callback_url] = fetch_key(h, :callback_url) unless fetch_key(h, :callback_url).nil?
      out[:redirect_url] = fetch_key(h, :redirect_url) unless fetch_key(h, :redirect_url).nil?
      out[:idempotency_key] = fetch_key(h, :idempotency_key) unless fetch_key(h, :idempotency_key).nil?
      out[:metadata] = fetch_key(h, :metadata) unless fetch_key(h, :metadata).nil?
      out
    end

    def fetch_key(hash, key)
      return hash[key] if hash.key?(key)
      return hash[key.to_s] if hash.key?(key.to_s)

      nil
    end

    def normalize_keys(hash)
      return {} if hash.nil?
      hash.each_with_object({}) do |(k, v), h|
        normalized = k.to_s.gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
                            .gsub(/([a-z0-9])([A-Z])/, '\\1_\\2')
                            .downcase.to_sym
        # First occurrence wins so { order_id: a, orderId: b } is deterministic.
        h[normalized] = v unless h.key?(normalized)
      end
    end
  end
end
