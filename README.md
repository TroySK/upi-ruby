# UPI — Free Zero-Commission UPI Payments for Ruby & Rails

Accept UPI payments directly into your bank account via PhonePe Business & Paytm Business free merchant APIs. Rs 0 per transaction.

## Requirements

- Ruby `>= 3.2.0`
- Runtime deps (installed automatically): `faraday ~> 2.x`, `rqrcode >= 2, < 4`, `chunky_png`
- Rails (`railties`) is **optional** — only needed for the Engine / webhook controller.

## Install

```ruby
gem "upi", "~> 1.0"
```

```bash
bundle install
```

## Zero-config via ENV (UPI_ prefix)

```bash
UPI_PROVIDER=phonepe
UPI_ENV=sandbox
UPI_MERCHANT_ID=MERCHANTUAT
UPI_SALT_KEY=your-salt-key
UPI_SALT_INDEX=1
# Paytm instead:
# UPI_PROVIDER=paytm
# UPI_MERCHANT_KEY=your-merchant-key
# UPI_WEBSITE=WEBSTAGING
```

```ruby
require "upi"
client = UPI::Client.from_env
```

Full ENV reference: `UPI_PROVIDER`, `UPI_ENV` (or `UPI_ENVIRONMENT`), `UPI_MERCHANT_ID`, `UPI_SALT_KEY`, `UPI_SALT_INDEX`, `UPI_MERCHANT_KEY`, `UPI_WEBSITE`, `UPI_TIMEOUT`, `UPI_DEBUG`, `UPI_CALLBACK_URL`, `UPI_REDIRECT_URL`, `UPI_MAX_RETRIES`, `UPI_RETRY_DELAY_MS`. See `.env.example`.

Notes:
- Invalid numeric ENV values (e.g. `UPI_TIMEOUT=abc`) are ignored and fall back to defaults — they never silently become `0`.
- `UPI_DEBUG` accepts `1/true/yes/on` (and `0/false/no/off`).

## Explicit config

```ruby
client = UPI::Client.new(
  provider: "phonepe",
  environment: "sandbox",
  credentials: { "merchantId" => "MERCHANTUAT", "saltKey" => "...", "saltIndex" => "1" }
)
```

## Global configure (Rails initializer)

```ruby
# config/initializers/upi.rb
UPI.configure do |c|
  c.provider = :phonepe
  c.environment = Rails.env.production? ? "production" : "sandbox"
  c.merchant_id = Rails.application.credentials.dig(:upi, :merchant_id)
  c.salt_key = Rails.application.credentials.dig(:upi, :salt_key)
  c.salt_index = "1"
end

client = UPI.client
```

Explicit overrides win over globals, and globals win over ENV:

```ruby
client = UPI.client(timeout: 10_000, debug: true)
```

## Key conventions

Request/option hashes accept **any** key style interchangeably — `:snake_case`, `"snake_case"`, `:camelCase`, `"camelCase"`, even all-caps acronyms (`"orderID"`, `"AMOUNT"` are normalized correctly):

```ruby
client.check_status("order_123", { expectedAmount: 50_000 })
client.check_status("order_123", { "expected_amount" => 50_000 })
```

`timeout:` accepts an Integer or numeric String; `debug:` accepts booleans or `"true"/"1"/"yes"/"on"` (and falsy `"false"/"0"/"off"/"no"`) strings.

## QR codes (no merchant account needed)

```ruby
uri = UPI::QR.build_upi_uri(vpa: "mybusiness@ybl", name: "My Business", amount: 500.0, order_id: "order_123")
links = UPI::QR.build_intent_links(uri)
qr = UPI::QR.generate_qr(vpa: "mybusiness@ybl", name: "My Business", amount: 500.0, order_id: "order_123")
# qr[:qr_image] -> data:image/png;base64,...  (render as <img src=...>)
svg = UPI::QR.generate_qr_svg(vpa: "mybusiness@ybl", name: "My Business", amount: 500.0, order_id: "order_123")
png_bytes = UPI::QR.generate_qr_png_bytes(vpa: "mybusiness@ybl", name: "My Business", amount: 500.0, order_id: "order_123")
```

Oversized payloads raise `UPI::InvalidConfigError("QR payload too large …")` instead of a raw `RQRCodeCore` error.

## Payments (PSP)

```ruby
payment = client.create_payment(
  amount: 50_000, order_id: "order_123", customer_phone: "9876543210",
  callback_url: "https://yoursite.com/upi/webhooks/phonepe",
  redirect_url: "https://yoursite.com/payment-complete"
)
# redirect user to payment[:payment_url]

# Status check retries transient (5xx/network) failures with
# exponential back-off + jitter. Tune per call or per client:
status = client.check_status("order_123", { expected_amount: 50_000 })
status = client.check_status("order_123", { max_retries: 0 }) # no retry

refund = client.create_refund(original_order_id: "order_123", refund_id: "refund_1", amount: 50_000)
# Paytm also requires the PSP transaction id:
refund = client.create_refund(original_order_id: "order_123", refund_id: "refund_1",
  amount: 50_000, provider_transaction_id: "PAYTM_TXN_ID")
```

Amounts are **paise integers** (`50_000` = Rs 500). Use `UPI::Utils::Currency.rupees_to_paise(500.0)` / `paise_to_rupees` to convert safely (rejects sub-paisa precision, `Infinity`/`NaN`, and non-numeric input).

## Webhooks

```ruby
event = client.verify_webhook(request.raw_post, request.headers["X-VERIFY"], { expected_amount: 50_000 })
puts event[:verified] # true/false
```

- PhonePe: signature is the `X-VERIFY` header (`sha256(base64_response + salt)###saltIndex`, constant-time compared).
- Paytm: pass the raw JSON body; the checksum is read from the header arg or from `CHECKSUMHASH`/`CHECKSUM`/`checksum`/`checkSum` inside the body.
- Opt-in replay protection: `verify_webhook(body, sig, enable_replay_protection: true)` rejects callbacks with stale/missing timestamps (default 300s tolerance, configurable via `timestamp_tolerance_seconds:`).
- `expected_amount:` marks tampered-amount callbacks as `verified: false` instead of raising.

## Error handling

```ruby
begin
  client.create_payment(amount: 50_000, order_id: "o1", customer_phone: "9876543210",
    callback_url: "https://a/c", redirect_url: "https://a/r")
rescue UPI::InvalidConfigError => e   # bad input / credentials (never retriable)
rescue UPI::NetworkError => e         # always retriable? == true
rescue UPI::PaymentError => e         # check e.retriable? before retrying
rescue UPI::RefundError => e
rescue UPI::Error => e                # base class: e.code, e.provider, e.cause
end
```

Every error carries `#code`, `#provider`, `#retriable?`, and `#cause` (the original exception).

## Rails integration (step by step)

Works with Rails 6+ (new or existing app). Takes ~10 minutes.

### Step 1 — Add the gem

```ruby
# Gemfile
gem "upi", "~> 1.0"
```

```bash
bundle install
```

### Step 2 — Store credentials

Do NOT hardcode secrets. Use Rails credentials (recommended) or ENV:

```bash
# Option A — Rails credentials (recommended)
rails credentials:edit
```

```yaml
upi:
  provider: phonepe
  merchant_id: MERCHANTUAT
  salt_key: YOUR_SALT_KEY
  salt_index: "1"
  # paytm instead:
  # provider: paytm
  # merchant_id: YOUR_MID
  # merchant_key: YOUR_MERCHANT_KEY
  # website: WEBSTAGING
```

```bash
# Option B — ENV vars (Docker / Render / Heroku)
UPI_PROVIDER=phonepe
UPI_ENV=sandbox
UPI_MERCHANT_ID=MERCHANTUAT
UPI_SALT_KEY=your-salt-key
UPI_SALT_INDEX=1
UPI_CALLBACK_URL=https://yoursite.com/upi/webhooks/phonepe
UPI_REDIRECT_URL=https://yoursite.com/payment-complete
```

### Step 3 — Create the initializer

```ruby
# config/initializers/upi.rb
UPI.configure do |c|
  c.provider = Rails.application.credentials.dig(:upi, :provider) || ENV["UPI_PROVIDER"] || :phonepe
  c.environment = Rails.env.production? ? "production" : "sandbox"
  c.merchant_id = Rails.application.credentials.dig(:upi, :merchant_id) || ENV["UPI_MERCHANT_ID"]
  c.salt_key = Rails.application.credentials.dig(:upi, :salt_key) || ENV["UPI_SALT_KEY"]
  c.salt_index = Rails.application.credentials.dig(:upi, :salt_index)&.to_s || ENV["UPI_SALT_INDEX"] || "1"
  # paytm:
  # c.merchant_key = Rails.application.credentials.dig(:upi, :merchant_key) || ENV["UPI_MERCHANT_KEY"]
  # c.website = Rails.application.credentials.dig(:upi, :website) || ENV["UPI_WEBSITE"]
  c.callback_url = ENV["UPI_CALLBACK_URL"]
  c.redirect_url = ENV["UPI_REDIRECT_URL"]
end
```

### Step 4 — Mount the webhook route

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount UPI::Engine => "/upi"
  # gives you: POST /upi/webhooks/:provider
end
```

Verify:

```bash
rails routes | grep upi
# => upi POST /upi/webhooks/:provider(.:format) upi/webhooks#create
```

### Step 5 — Create a checkout endpoint

```ruby
# app/controllers/payments_controller.rb
class PaymentsController < ApplicationController
  def create
    order = Order.create!(amount_paise: 50_000, status: "pending")
    client = UPI.client # built from the initializer above
    payment = client.create_payment(
      amount: order.amount_paise,
      order_id: "order_#{order.id}",
      customer_phone: params[:phone],
      customer_email: params[:email],
      callback_url: upi_webhook_url(provider: "phonepe"),
      # or: ENV["UPI_CALLBACK_URL"],
      redirect_url: payment_done_url
    )
    order.update!(provider_order_id: payment[:order_id])
    redirect_to payment[:payment_url], allow_other_host: true
  rescue UPI::Error => e
    redirect_to checkout_path, alert: "Payment failed to start: #{e.message}"
  end

  def done
    # User returns here after paying. The SOURCE OF TRUTH is the
    # server-to-server webhook below — always re-check status:
    status = UPI.client.check_status(params[:order_id] || "order_#{params[:id]}")
    # status[:status] => "SUCCESS" | "PENDING" | "FAILED"
  end
end
```

### Step 6 — Handle the webhook (fulfil orders)

The mounted engine controller auto-verifies the signature and answers `200`/`401` for you. If you need to run business logic (mark order paid, send receipt), add your own controller wrapping it:

```ruby
# app/controllers/upi_callbacks_controller.rb
class UpiCallbacksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    client = UPI.client(provider: params[:provider])
    event = client.verify_webhook(
      request.raw_post,
      request.headers["X-VERIFY"] || params["CHECKSUMHASH"].to_s,
      expected_amount: expected_amount_for(params),
      enable_replay_protection: true
    )
    if event[:verified] && event[:status] == "SUCCESS"
      Order.find_by(provider_order_id: event[:order_id])&.update!(status: "paid")
      head :ok
    elsif event[:verified]
      head :ok # signature valid, payment still pending/failed — nothing to fulfil
    else
      head :unauthorized
    end
  end

  private

  def expected_amount_for(params)
    # Look up YOUR order and return its paise amount so tampered
    # callbacks verify as false. Return nil to skip the check.
    Order.find_by(provider_order_id: params[:ORDERID] || params[:order_id])&.amount_paise
  end
end
```

```ruby
# config/routes.rb — if you use your own controller instead of the engine's:
# post "upi/webhooks/:provider" => "upi_callbacks#create"
```

### Step 7 — Harden production

```ruby
# config/environments/production.rb (or application.rb)
# 1. Only accept callbacks from PSP IPs:
config.middleware.use UPI::Utils::IpGuard::Middleware, provider: :phonepe, trust_proxy: true
# 2. Never log secrets; keep debug off:
#    UPI_DEBUG=false (default)
```

Production checklist:
- [ ] `UPI_ENV=production`, real `MERCHANT_ID` / `SALT_KEY` (PhonePe) or `MERCHANT_KEY` (Paytm)
- [ ] `callback_url` / `redirect_url` are `https://` (enforced automatically)
- [ ] Behind a proxy (Heroku/Render/NGINX): `trust_proxy: true` so the IP guard reads the proxy-appended `X-Forwarded-For`
- [ ] Webhook uses `expected_amount:` + `enable_replay_protection: true`
- [ ] `redirect_url` ("payment done" page) re-checks `check_status` — never trust it alone

### Step 8 — Test end to end

```bash
rails server
# 1. POST to your checkout -> redirected to PSP sandbox page
# 2. Pay with a sandbox test account
# 3. PSP calls POST /upi/webhooks/:provider -> 200
# 4. rails console: Order.last.status # => "paid"
# 5. Sandbox check: UPI.client.check_status("order_1", expected_amount: 50_000)
```

QR-only flow (no PSP account needed — static collect QR):

```erb
<%# app/views/products/show.html.erb %>
<% qr = UPI::QR.generate_qr(vpa: "mybusiness@ybl", name: "My Business", amount: @product.price_rupees, order_id: "qr_#{@product.id}") %>
<%= image_tag qr[:qr_image], alt: "Pay with any UPI app" %>
```

IP allowlisting middleware (Rack):

```ruby
config.middleware.use UPI::Utils::IpGuard::Middleware, provider: :phonepe, trust_proxy: true
```

Security notes:
- With `trust_proxy: true`, the **rightmost** `X-Forwarded-For` entry is used (the one your proxy appended) — left entries are client-controlled and never trusted.
- `callback_url`/`redirect_url` must be `http(s)://` (or `upi://`); `https://` is enforced in production and `javascript:/data:/vbscript:/file:` schemes are rejected.
- Secrets passed through the debug logger are auto-redacted.

## Testing

```bash
bundle install
bundle exec rake test
```

MIT — free for commercial and personal use.
