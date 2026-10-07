# frozen_string_literal: true

require_relative "test_helper"

class EnvConfigTest < Test::Unit::TestCase
  def setup
    @saved_env = ENV.to_h
  end

  def teardown
    ENV.replace(@saved_env)
    UPI.reset_configuration!
  end

  def test_reads_upi_env_vars
    ENV["UPI_PROVIDER"] = "phonepe"
    ENV["UPI_ENV"] = "sandbox"
    ENV["UPI_MERCHANT_ID"] = "MERCHANTUAT"
    ENV["UPI_SALT_KEY"] = "ab1c2d3e-f4g5-6789-abcd-ef1234567890"
    ENV["UPI_SALT_INDEX"] = "1"
    cfg = UPI::Configuration.from_env
    assert_equal("phonepe", cfg.normalized_provider)
    assert_equal("MERCHANTUAT", cfg.effective_credentials["merchantId"])
    client = UPI::Client.from_env
    assert_equal("phonepe", client.provider)
  end

  def test_explicit_values_win_over_env
    ENV["UPI_PROVIDER"] = "paytm"
    cfg = UPI::Configuration.from_env(provider: "phonepe")
    assert_equal("phonepe", cfg.normalized_provider)
  end

  def test_supports_block_configure
    UPI.configure { |c| c.provider = "paytm"; c.environment = "sandbox" }
    assert_equal("paytm", UPI.configuration.provider)
  end
end

