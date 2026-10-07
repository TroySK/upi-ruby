# frozen_string_literal: true

module UPI
  module Utils
    # Webhook origin verification.
    # Rack-compatible middleware + Rails helper.
    module IpGuard
      PHONEPE_CIDRS = [
        "163.53.76.0/24", "163.53.77.0/24", "163.53.78.0/24", "163.53.79.0/24",
        "103.125.24.0/24", "103.125.25.0/24", "103.116.34.16/29", "103.116.32.16/29",
        "103.116.33.8/30", "103.116.33.136/30", "103.116.34.0/24", "103.116.32.0/24",
        "103.116.33.0/24", "103.243.35.242/32"
      ].freeze

      PAYTM_CIDRS = [
        "103.58.196.0/24", "103.58.197.0/24", "103.58.198.0/24", "182.72.68.0/24"
      ].freeze

      module_function

      def ipv4_to_int(ip)
        parts = ip.to_s.split(".")
        return nil unless parts.length == 4
        result = 0
        parts.each do |part|
          octet = Integer(part, 10) rescue nil
          return nil if octet.nil? || octet < 0 || octet > 255
          result = (result << 8) | octet
        end
        result & 0xFFFFFFFF
      end

      def ip_in_cidr?(ip, cidr)
        clean = ip.to_s.sub(/\A::ffff:/, "")
        return false unless clean.match?(/\A\d{1,3}(\.\d{1,3}){3}\z/)
        parts = cidr.to_s.split("/")
        return false unless parts.length == 2
        network_str, prefix_str = parts
        return false unless prefix_str.match?(/\A\d+\z/)
        prefix = prefix_str.to_i
        return false unless prefix.between?(0, 32)
        ip_int = ipv4_to_int(clean)
        net_int = ipv4_to_int(network_str)
        return false if ip_int.nil? || net_int.nil?
        mask = prefix.zero? ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
        (ip_int & mask) == (net_int & mask)
      end

      def allowed?(ip, cidrs)
        return false if ip.nil? || ip.to_s.strip.empty?
        cidrs.any? { |c| ip_in_cidr?(ip, c) }
      end

      # Rack middleware factory. Usage in Rails:
      #   config.middleware.use UPI::Utils::IpGuard::Middleware, provider: :phonepe
      class Middleware
        def initialize(app, provider:, additional_cidrs: [], trust_proxy: false, on_blocked: nil)
          @app = app
          base = provider.to_s == "paytm" ? PAYTM_CIDRS : PHONEPE_CIDRS
          @cidrs = base + additional_cidrs
          @trust_proxy = trust_proxy
          @on_blocked = on_blocked
        end

        def call(env)
          ip = resolve_ip(env)
          if ip && IpGuard.allowed?(ip, @cidrs)
            @app.call(env)
          else
            @on_blocked&.call(ip, env)
            [403, { "Content-Type" => "text/plain" }, ["Forbidden"]]
          end
        end

        private

        def resolve_ip(env)
          if @trust_proxy
            forwarded = env["HTTP_X_FORWARDED_FOR"]
            if forwarded && !forwarded.strip.empty?
              # Rightmost entry is the one appended by our trusted proxy;
              # left entries are client-controlled and must not be trusted.
              return forwarded.split(",").last.strip
            end
          end
          (env["REMOTE_ADDR"] || "").to_s.strip
        end
      end
    end
  end
end
