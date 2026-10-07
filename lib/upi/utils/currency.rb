# frozen_string_literal: true

module UPI
  module Utils
    # Currency helpers.
    module Currency
      module_function

      # Safely convert rupees (decimal) to paise (integer).
      # Rejects sub-paisa precision to avoid silent rounding drift.
      def rupees_to_paise(rupees)
        unless rupees.is_a?(Numeric) && rupees.finite?
          raise TypeError, "Amount in rupees must be a valid number"
        end
        raise RangeError, "Amount in rupees must be greater than zero" unless rupees > 0
        unless rupees.to_s.match?(/\A\d+(\.\d{1,2})?\z/)
          raise RangeError, "Amount in rupees must not exceed 2 decimal places"
        end
        (rupees * 100).round
      end

      def paise_to_rupees(paise)
        int = Integer(paise)
        (int / 100.0).round(2)
      rescue ArgumentError, TypeError
        raise TypeError, "Amount in paise must be a valid integer"
      end
    end
  end
end
