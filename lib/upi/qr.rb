# frozen_string_literal: true

require "uri"

module UPI
  # NPCI-compliant UPI QR generation.
  module QR
    module_function

    def build_upi_uri(vpa:, name:, amount:, order_id:, note: nil, mode: "fixed", mc: nil)
      UPI::Utils::Validation.validate_qr_request(
        { vpa: vpa, name: name, amount: amount, order_id: order_id, note: note }
      )
      params = {
        "pa" => vpa.to_s, "pn" => name.to_s,
        "am" => format("%.2f", amount),
        "tr" => order_id.to_s, "cu" => "INR"
      }
      params["mode"] = "04" if (mode || "fixed").to_s == "fixed"
      params["mc"] = mc.to_s unless mc.nil? || mc.to_s.strip.empty?
      params["tn"] = note.to_s unless note.nil? || note.to_s.empty?
      "upi://pay?#{URI.encode_www_form(params)}"
    end

    def build_intent_links(upi_uri)
      uri_str = upi_uri.to_s
      query = uri_str.include?("?") ? uri_str.split("?", 2).last : uri_str
      {
        generic: uri_str,
        phonepe: "phonepe://pay?#{query}",
        gpay: "tez://upi/pay?#{query}",
        paytm: "paytmmp://pay?#{query}",
        bhim: "upi://pay?#{query}"
      }
    end

    def generate_qr(vpa:, name:, amount:, order_id:, **opts)
      require "rqrcode"
      uri = build_upi_uri(vpa: vpa, name: name, amount: amount, order_id: order_id, **opts)
      qr = RQRCode::QRCode.new(uri, level: :h)
      png = qr.as_png(size: 400, border_modules: 2)
      {
        upi_uri: uri,
        qr_image: "data:image/png;base64,#{[png.to_blob].pack("m0")}",
        order_id: order_id, amount: amount
      }
    rescue RQRCodeCore::QRCodeRunTimeError => e
      raise UPI::InvalidConfigError, "QR payload too large: #{e.message}"
    end

    def generate_qr_svg(vpa:, name:, amount:, order_id:, **opts)
      require "rqrcode"
      uri = build_upi_uri(vpa: vpa, name: name, amount: amount, order_id: order_id, **opts)
      RQRCode::QRCode.new(uri, level: :h).as_svg
    rescue RQRCodeCore::QRCodeRunTimeError => e
      raise UPI::InvalidConfigError, "QR payload too large: #{e.message}"
    end

    def generate_qr_png_bytes(vpa:, name:, amount:, order_id:, **opts)
      require "rqrcode"
      uri = build_upi_uri(vpa: vpa, name: name, amount: amount, order_id: order_id, **opts)
      RQRCode::QRCode.new(uri, level: :h).as_png(size: 400, border_modules: 2).to_blob
    rescue RQRCodeCore::QRCodeRunTimeError => e
      raise UPI::InvalidConfigError, "QR payload too large: #{e.message}"
    end
  end
end
