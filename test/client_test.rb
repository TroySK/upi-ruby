# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Test::Unit::TestCase
  def phonepe_creds
    { "merchantId" => "MERCHANTUAT", "saltKey" => "ab1c2d3e-f4g5-6789-abcd-ef1234567890", "saltIndex" => "1" }
  end

  def test_initialises_with_phonepe_config
    c = UPI::Client.new(provider: "phonepe", environment: "sandbox", credentials: phonepe_creds)
    assert_equal("phonepe", c.provider)
    assert_equal("sandbox", c.environment)
  end

  def test_initialises_with_paytm_config
    c = UPI::Client.new(provider: "paytm", environment: "sandbox",
      credentials: { "merchantId" => "PAYTM_MID_12345", "merchantKey" => "ab1c2d3e4f5g6h7i8j9k0l1m2n3o4p5q" })
    assert_equal("paytm", c.provider)
  end

  def test_rejects_invalid_provider
    assert_raise(UPI::InvalidConfigError) do
      UPI::Client.new(provider: "razorpay", environment: "sandbox", credentials: {})
    end
  end

  def test_rejects_missing_credentials
    assert_raise(UPI::InvalidConfigError) do
      UPI::Client.new(provider: "phonepe", environment: "sandbox", credentials: {})
    end
  end

  def test_rejects_placeholder_credentials
    err = assert_raise(UPI::InvalidConfigError) do
      UPI::Client.new(provider: "phonepe", environment: "sandbox",
        credentials: { "merchantId" => "MERCHANTUAT", "saltKey" => "your_salt_key_here", "saltIndex" => "1" })
    end
    assert_match(/placeholder/i, err.message)
  end

  def test_validates_order_id_on_check_status
    c = UPI::Client.new(provider: "phonepe", environment: "sandbox", credentials: phonepe_creds)
    err = assert_raise(UPI::InvalidConfigError) { c.check_status("../../etc/passwd") }
    assert_match(/alphanumeric/, err.message)
  end

  def test_builds_a_upi_link
    c = UPI::Client.new(provider: "phonepe", environment: "sandbox", credentials: phonepe_creds)
    link = c.build_upi_link(vpa: "shop@paytm", name: "My Shop", amount: 299.99, order_id: "link_test")
    assert_include(link, "upi://pay?")
    assert_include(link, "am=299.99")
  end

  def test_builds_intent_links
    c = UPI::Client.new(provider: "phonepe", environment: "sandbox", credentials: phonepe_creds)
    links = c.build_intent_links(vpa: "biz@ybl", name: "Biz", amount: 100, order_id: "intent_test")
    assert_include(links[:phonepe], "phonepe://pay?")
    assert_include(links[:gpay], "tez://upi/pay?")
  end

  def test_exposes_the_adapter
    c = UPI::Client.new(provider: "phonepe", environment: "sandbox", credentials: phonepe_creds)
    assert_equal("phonepe", c.get_adapter.provider)
  end
end

