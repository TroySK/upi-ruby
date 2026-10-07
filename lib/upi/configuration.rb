# frozen_string_literal: true

module UPI
  # Pluggable, ENV-driven configuration.
  #
  # All settings can come from ENV vars (UPI_ prefix), explicit kwargs,
  # or a mix (explicit wins). Also supports Rails credentials / block config.
  #
  #   ENV:
  #     UPI_PROVIDER              phonepe | paytm
  #     UPI_ENV / UPI_ENVIRONMENT sandbox | production
  #     UPI_MERCHANT_ID
  #     UPI_SALT_KEY              (PhonePe)
  #     UPI_SALT_INDEX            (PhonePe, default "1")
  #     UPI_MERCHANT_KEY          (Paytm)
  #     UPI_WEBSITE               (Paytm, optional)
  #     UPI_TIMEOUT               (ms, default 30000)
  #     UPI_DEBUG                 "true"/"1"
  #     UPI_CALLBACK_URL
  #     UPI_REDIRECT_URL
  #
  #   Ruby:
  #     UPI.configure do |c|
  #       c.provider = :phonepe
  #       c.merchant_id = "MERCHANTUAT"
  #     end
  #     client = UPI.client # built from global config
  #     client = UPI::Client.from_env
  #     client = UPI::Client.new(provider: "paytm", environment: "sandbox", credentials: {...})
  class Configuration
    attr_accessor :provider, :environment, :credentials,
                  :merchant_id, :salt_key, :salt_index, :merchant_key, :website,
                  :timeout, :debug, :logger,
                  :callback_url, :redirect_url,
                  :max_retries, :retry_delay_ms

    def initialize(attrs = {})
      @provider      = attrs[:provider] || attrs["provider"]
      @environment   = attrs[:environment] || attrs["environment"]
      @credentials   = attrs[:credentials] || attrs["credentials"]
      @merchant_id   = attrs[:merchant_id] || attrs["merchant_id"]
      @salt_key      = attrs[:salt_key] || attrs["salt_key"]
      @salt_index    = attrs[:salt_index] || attrs["salt_index"]
      @merchant_key  = attrs[:merchant_key] || attrs["merchant_key"]
      @website       = attrs[:website] || attrs["website"]
      @timeout       = attrs[:timeout] || attrs["timeout"]
      @debug         = attrs.key?(:debug) ? attrs[:debug] : attrs["debug"]
      @logger        = attrs[:logger] || attrs["logger"]
      @callback_url  = attrs[:callback_url] || attrs["callback_url"]
      @redirect_url  = attrs[:redirect_url] || attrs["redirect_url"]
      @max_retries   = attrs[:max_retries] || attrs["max_retries"]
      @retry_delay_ms = attrs[:retry_delay_ms] || attrs["retry_delay_ms"]
      apply_env_defaults!
    end

    # Fill any blank field from UPI_* ENV. Explicit values win.
    def apply_env_defaults!
      @provider     ||= pick_env("UPI_PROVIDER")
      @environment  ||= pick_env("UPI_ENV") || pick_env("UPI_ENVIRONMENT") || "sandbox"
      @merchant_id  ||= pick_env("UPI_MERCHANT_ID")
      @salt_key     ||= pick_env("UPI_SALT_KEY")
      @salt_index   ||= pick_env("UPI_SALT_INDEX") || "1"
      @merchant_key ||= pick_env("UPI_MERCHANT_KEY")
      @website      ||= pick_env("UPI_WEBSITE")
      @timeout = @timeout.nil? ? parse_timeout(pick_env("UPI_TIMEOUT")) : parse_timeout(@timeout)
      @debug        = env_flag("UPI_DEBUG") if @debug.nil?
      @debug        = coerce_flag(@debug)
      @callback_url ||= pick_env("UPI_CALLBACK_URL")
      @redirect_url ||= pick_env("UPI_REDIRECT_URL")
      @max_retries  = @max_retries.nil? ? parse_int(pick_env("UPI_MAX_RETRIES")) : parse_int(@max_retries)
      @retry_delay_ms = @retry_delay_ms.nil? ? parse_int(pick_env("UPI_RETRY_DELAY_MS")) : parse_int(@retry_delay_ms)
      self
    end

    def self.from_env(overrides = {})
      new(overrides).apply_env_defaults!
    end

    # Normalised provider string.
    def normalized_provider
      provider.to_s.downcase
    end

    def normalized_environment
      environment.to_s.downcase
    end

    # Build the credentials hash the Client/adapters expect.
    def effective_credentials
      return credentials if credentials && !credentials.empty?

      case normalized_provider
      when "phonepe"
        { "merchantId" => merchant_id.to_s, "saltKey" => salt_key.to_s,
          "saltIndex" => (salt_index || "1").to_s }
      when "paytm"
        h = { "merchantId" => merchant_id.to_s, "merchantKey" => merchant_key.to_s }
        h["website"] = website.to_s unless website.nil? || website.to_s.empty?
        h
      else
        {}
      end
    end

    def effective_timeout
      t = @timeout.nil? ? 30_000 : parse_timeout(@timeout)
      t.nil? ? 30_000 : t
    end

    def debug?
      !!debug
    end

    def to_client_options
      opts = { timeout: effective_timeout, debug: debug? }
      opts[:logger] = logger if logger
      opts[:max_retries] = max_retries unless max_retries.nil?
      opts[:retry_delay_ms] = retry_delay_ms unless retry_delay_ms.nil?
      opts
    end

    private

    # Strict integer parsing: "abc"/"" → nil so invalid ENV never becomes 0.
    def parse_int(value)
      return nil if value.nil?
      return value if value.is_a?(Integer)
      str = value.to_s.strip
      return nil unless str.match?(/\A[+-]?\d+\z/)

      str.to_i
    end

    def parse_timeout(value)
      parse_int(value)
    end

    def coerce_flag(value)
      return value if value.nil? || value == true || value == false
      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end

    def pick_env(key)
      v = ENV[key]
      v = v.strip if v.respond_to?(:strip)
      (v.nil? || v.empty?) ? nil : v
    end

    def env_flag(key)
      v = ENV[key]
      return nil if v.nil?
      %w[1 true yes on].include?(v.to_s.strip.downcase)
    end
  end
end
