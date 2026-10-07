# frozen_string_literal: true

require "openssl"

module UPI
  module Utils
    # Cryptographic helpers.
    # Uses only Ruby stdlib OpenSSL — no extra deps.
    module Crypto
      PAYTM_IV = [64, 64, 64, 64, 38, 38, 38, 38, 35, 35, 35, 35, 36, 36, 36, 36].pack("C*").freeze

      module_function

      # HMAC-SHA256 hex digest.
      def hmac_sha256(data, secret)
        OpenSSL::HMAC.hexdigest("SHA256", secret, data)
      end

      # SHA256 hex digest (used by PhonePe for checksum).
      def sha256(data)
        OpenSSL::Digest::SHA256.hexdigest(data)
      end

      # Constant-time string comparison.
      # Prevents timing side-channels in webhook verification.
      def constant_time_equal(a, b)
        a = a.to_s
        b = b.to_s
        # OpenSSL.fixed_length_secure_compare requires equal length;
        # pad both sides then check length equality afterwards.
        max_len = [a.bytesize, b.bytesize, 1].max
        padded_a = a.b.ljust(max_len, "\x00")
        padded_b = b.b.ljust(max_len, "\x00")
        contents_equal = OpenSSL.fixed_length_secure_compare(padded_a, padded_b)
        a.bytesize == b.bytesize && contents_equal
      rescue OpenSSL::OpenSSLError
        false
      end

      # Check if a webhook timestamp is fresh (prevents replay attacks).
      # Supports Unix timestamps (seconds/ms as Numeric or String) and ISO strings.
      def timestamp_fresh?(timestamp, tolerance_seconds = 300)
        return false unless timestamp.is_a?(Numeric) || timestamp.is_a?(String)

        webhook_time =
          case timestamp
          when Numeric then timestamp.to_f
          when /\A\d+\z/ then timestamp.to_i.to_f
          when /\A\d+\.\d+\z/ then timestamp.to_f
          else
            str = timestamp.to_s
            # Paytm callbacks send "YYYY-MM-DD HH:mm:ss.S" in IST without TZ.
            if str.match?(/\A\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}/) &&
               !str.match?(/[+-]\d{2}:?\d{2}\z/) && !str.match?(/Z\z/i)
              str = "#{str.strip} +05:30"
            end
            begin
              require "time"
              Time.parse(str).to_f
            rescue ArgumentError
              return false
            end
          end

        return false unless webhook_time.finite?

        # Convert milliseconds to seconds.
        webhook_time /= 1000.0 if webhook_time > 99_999_999_999

        (Time.now.to_f.floor - webhook_time.floor).abs <= tolerance_seconds
      end

      # Convert a param hash to Paytm's pipe-delimited sorted string.
      # Keys sorted alphabetically, nil → "".
      def paytm_params_string(params)
        keys = params.keys.map(&:to_s).uniq.sort
        keys.map do |k|
          v = params.key?(k) ? params[k] : params[k.to_sym]
          v = params[k.to_sym] if v.nil? && params.key?(k.to_sym)
          # Preserve false (don't let `||` swallow it); nil → "".
          v.nil? ? "" : v.to_s
        end.join("|")
      end

      # Generate a Paytm checksum.
      # 1. random 4-char salt 2. SHA256(params|salt) 3. hash+salt
      # 4. AES-128-CBC encrypt with merchantKey[0,16] + static IV.
      def generate_paytm_checksum(params_string, merchant_key)
        require "securerandom"
        key = merchant_key.to_s
        unless key.bytesize >= 16
          raise UPI::InvalidConfigError.new("Paytm merchantKey must be >= 16 chars.", "paytm")
        end
        key = key[0, 16]
        salt = SecureRandom.hex(4)[0, 4]
        hash = OpenSSL::Digest::SHA256.hexdigest("#{params_string}|#{salt}")
        hash_with_salt = "#{hash}#{salt}"
        cipher = OpenSSL::Cipher.new("AES-128-CBC")
        cipher.encrypt
        cipher.key = key
        cipher.iv = PAYTM_IV
        encrypted = cipher.update(hash_with_salt) + cipher.final
        [encrypted].pack("m0")
      end

      # Verify a Paytm checksum by decrypt + recompute + constant-time compare.
      def verify_paytm_checksum(params_string, merchant_key, checksum)
        key = merchant_key.to_s
        return false if key.bytesize < 16
        key = key[0, 16]
        decipher = OpenSSL::Cipher.new("AES-128-CBC")
        decipher.decrypt
        decipher.key = key
        decipher.iv = PAYTM_IV
        decrypted = decipher.update(checksum.unpack1("m")) + decipher.final
        salt = decrypted[-4, 4]
        hash = decrypted[0...-4]
        expected = OpenSSL::Digest::SHA256.hexdigest("#{params_string}|#{salt}")
        constant_time_equal(hash, expected)
      rescue StandardError
        false
      end
    end
  end
end
