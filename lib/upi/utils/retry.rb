# frozen_string_literal: true

module UPI
  module Utils
    # Transient-failure retry with exponential back-off.
    # Retries UPI::Error with retriable? == true.
    module Retry
      module_function

      def with_retry(max_attempts: 3, base_delay_ms: 1000)
        max = max_attempts.nil? ? 3 : max_attempts.to_i
        max = 1 if max < 1
        delay_ms = base_delay_ms.nil? ? 1000 : base_delay_ms.to_f
        delay_ms = 0.0 if delay_ms.negative?
        attempts = 0
        begin
          attempts += 1
          return yield
        rescue UPI::Error => e
          raise unless e.retriable? && attempts < max
          delay = delay_ms * (2**(attempts - 1)) / 1000.0
          # Full jitter: randomize 50–100% of the exponential delay so
          # concurrent clients don't retry in lock-step (thundering herd).
          delay *= (0.5 + rand * 0.5) if delay.positive?
          sleep(delay) if delay.positive?
          retry
        end
      end
    end
  end
end
