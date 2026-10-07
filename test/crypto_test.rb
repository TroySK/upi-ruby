# frozen_string_literal: true

require_relative "test_helper"

class CryptoTest < Test::Unit::TestCase
  def test_hmac_sha256_matches_known_vector
    assert_equal(
      "88aab3ede8d3adf94d26ab90d3bafd4a2083070c3bcce9c014ee04a443847c0b",
      UPI::Utils::Crypto.hmac_sha256("hello", "secret")
    )
  end

  def test_sha256_matches_known_vector
    assert_equal(
      "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
      UPI::Utils::Crypto.sha256("hello")
    )
  end

  def test_constant_time_equal
    assert_equal(true, UPI::Utils::Crypto.constant_time_equal("abc", "abc"))
    assert_equal(false, UPI::Utils::Crypto.constant_time_equal("abc", "def"))
    assert_equal(false, UPI::Utils::Crypto.constant_time_equal("abc", "abcd"))
  end

  def test_paytm_checksum_roundtrip
    params = { "ORDERID" => "o123", "MID" => "M123", "TXNAMOUNT" => "500.00" }
    str = UPI::Utils::Crypto.paytm_params_string(params)
    checksum = UPI::Utils::Crypto.generate_paytm_checksum(str, "1234567890123456")
    assert_equal(true, UPI::Utils::Crypto.verify_paytm_checksum(str, "1234567890123456", checksum))
    assert_equal(false, UPI::Utils::Crypto.verify_paytm_checksum("tampered", "1234567890123456", checksum))
  end

  def test_rupees_to_paise
    assert_equal(599, UPI::Utils::Currency.rupees_to_paise(5.99))
    assert_raise(RangeError) { UPI::Utils::Currency.rupees_to_paise(5.999) }
  end

  def test_sanitize_psp_error_extracts_safe_fields
    raw = %q({"code":"PAYMENT_FAILED","message":"Insufficient funds","internalTrace":"abc123"})
    assert_include(UPI::Utils::Sanitize.sanitize_psp_error(raw), "PAYMENT_FAILED")
  end
end

