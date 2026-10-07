# frozen_string_literal: true

module UPI
  # Base error for all UPI failures.
  class Error < StandardError
    attr_reader :code, :provider, :retriable, :cause

    def initialize(message, code: "UPI_ERROR", provider: nil, retriable: false, cause: nil)
      super(message)
      @code = code
      @provider = provider
      @retriable = retriable
      @cause = cause
      set_backtrace(cause.backtrace) if cause.is_a?(Exception) && backtrace.nil?
    end

    def retriable?
      !!@retriable
    end
  end

  # Invalid configuration (missing credentials, bad provider name, etc.)
  class InvalidConfigError < Error
    def initialize(message, provider = nil)
      super(message, code: "INVALID_CONFIG", provider: provider, retriable: false)
    end
  end

  # Payment creation or verification failed
  class PaymentError < Error
    def initialize(message, provider: nil, retriable: false, cause: nil)
      super(message, code: "PAYMENT_ERROR", provider: provider, retriable: retriable, cause: cause)
    end
  end

  # Webhook signature verification failed — security event
  class WebhookVerificationError < Error
    def initialize(message, provider = nil)
      super(message, code: "WEBHOOK_VERIFICATION_FAILED", provider: provider, retriable: false)
    end
  end

  # Network error — always retriable
  class NetworkError < Error
    def initialize(message, provider: nil, cause: nil)
      super(message, code: "NETWORK_ERROR", provider: provider, retriable: true, cause: cause)
    end
  end

  # Refund initiation or status check failed
  class RefundError < Error
    def initialize(message, provider: nil, retriable: false, cause: nil)
      super(message, code: "REFUND_ERROR", provider: provider, retriable: retriable, cause: cause)
    end
  end
end
