# frozen_string_literal: true

require "time"

module UPI
  module Utils
    # Logger with secret auto-redaction.
    class Logger
      SENSITIVE = %w[saltkey merchantkey secret password token apikey salt checksum verify].freeze

      def initialize(debug: false, logger: nil)
        @enabled = !!debug
        @custom = logger
      end

      def log(level, message, data = nil)
        return unless @enabled || %i[warn error].include?(level.to_sym)
        masked = data ? self.class.mask_secrets(data) : nil
        if @custom
          if @custom.respond_to?(:call)
            @custom.call(level, message, masked)
          elsif @custom.respond_to?(level.to_sym)
            @custom.public_send(level.to_sym, "#{message} #{masked.inspect}")
          elsif @custom.respond_to?(:add) || @custom.respond_to?(:log)
            meth = @custom.respond_to?(:add) ? :add : :log
            @custom.public_send(meth, level.to_sym, "#{message} #{masked.inspect}")
          else
            raise UPI::InvalidConfigError, "Custom logger must respond to call, #{level}, add, or log"
          end
          return
        end
        prefix = "#{Time.now.utc.iso8601} [UPI]:#{level.to_s.upcase}"
        out = level.to_s == "error" ? $stderr : $stdout
        out.puts("#{prefix} #{message} #{masked.inspect}")
      end

      def debug(msg, data = nil) = log(:debug, msg, data)
      def info(msg, data = nil) = log(:info, msg, data)
      def warn(msg, data = nil) = log(:warn, msg, data)
      def error(msg, data = nil) = log(:error, msg, data)

      def self.mask_secrets(data)
        return data if data.nil? || (!data.is_a?(Hash) && !data.is_a?(Array))
        return data.map { |v| mask_secrets(v) } if data.is_a?(Array)
        data.each_with_object({}) do |(k, v), out|
          if sensitive_key?(k.to_s) && v.is_a?(String) && !v.empty?
            out[k] = mask_value(v)
          elsif v.is_a?(Hash) || v.is_a?(Array)
            out[k] = mask_secrets(v)
          else
            out[k] = v
          end
        end
      end

      def self.sensitive_key?(key)
        k = key.downcase.gsub(/[_.\-\s]/, "")
        return true if SENSITIVE.include?(k)
        # Substring match only for unambiguous long tokens — short ones
        # like "key" over-redact (monkey, turkey, keyboard...).
        k.include?("password") || k.include?("passwd") || k.include?("secret") ||
          k.include?("saltkey") || k.include?("merchantkey") || k.include?("apikey") ||
          k.include?("accesstoken") || k.include?("refreshtoken")
      end

      def self.mask_value(value)
        str = value.to_s
        return "***REDACTED***" if str.length < 12
        "#{str[0, 4]}#{"*" * [str.length - 8, 16].min}#{str[-4, 4]}"
      end
    end
  end
end
