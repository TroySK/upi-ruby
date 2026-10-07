# frozen_string_literal: true

module UPI
  module Utils
    # Safe extraction of diagnostics from PSP error bodies.
    module Sanitize
      SAFE_FIELDS = %w[message code resultMsg resultCode description].freeze

      module_function

      def sanitize_psp_error(raw_body, max_length = 150)
        return "Upstream provider returned an unreadable response." unless raw_body.is_a?(String) && !raw_body.empty?

        begin
          require "json"
          parsed = JSON.parse(raw_body)
          return "Upstream provider returned an error response." unless parsed.is_a?(Hash)

          candidates = [parsed]
          parsed.each_value { |v| candidates << v if v.is_a?(Hash) }

          parts = []
          candidates.each do |obj|
            SAFE_FIELDS.each do |field|
              val = obj[field]
              next unless val.is_a?(String) && !val.strip.empty?
              parts << val.strip unless parts.include?(val.strip)
            end
          end

          return "Upstream provider returned an error response." if parts.empty?

          joined = parts.join(" — ")
          joined.length > max_length ? "#{joined[0, max_length]}…" : joined
        rescue JSON::ParserError
          "Upstream provider returned an unrecognised error response."
        end
      end
    end
  end
end
