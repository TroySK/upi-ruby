# Changelog

## [1.0.0]

- `UPI::Client`, PhonePe + Paytm adapters (Faraday), QR module (rqrcode), crypto/validation/currency/sanitize/retry/logger/ip-guard utils.
- Pluggable config: `UPI_*` ENV vars, explicit kwargs, `UPI.configure` block, `Client.from_env`.
- Rails Engine with `POST /upi/webhooks/:provider` controller + Rack IP-guard middleware.
- test-unit suite: 18 examples covering client init, crypto vectors, Paytm checksum roundtrip, ENV config.
