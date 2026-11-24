require "net/http"

module Higgsfield
  # Thin client for the Higgsfield API (https://docs.higgsfield.ai).
  #
  #   client = Higgsfield::Client.new
  #   url = client.upload(io, "image/jpeg")
  #   request = client.submit("/xai/grok-imagine-image-2.0", { prompt:, image_urls: [ url ] }, idempotency_key: "photo-1")
  #   client.status(request["status_url"]) # => { "status" => "completed", "images" => [ { "url" => ... } ] }
  class Client
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60

    def self.config
      Rails.application.config_for(:higgsfield)
    end

    def initialize(config = self.class.config)
      @base_url = config[:base_url]
      id, secret = config[:key_id].to_s.strip, config[:key_secret].to_s.strip
      # The console hands out a single "<id>:<secret>" key; accept it in either variable.
      @credentials = config[:api_key].to_s.strip.presence || (secret.present? ? "#{id}:#{secret}" : id)
    end

    def configured?
      id, secret = @credentials.to_s.split(":", 2)
      id.present? && secret.present?
    end

    # Uploads a file to Higgsfield storage and returns its public URL.
    def upload(io, content_type)
      target = post_json("/files/generate-upload-url", { content_type: content_type })
      uri = URI(target.fetch("upload_url"))
      request = Net::HTTP::Put.new(uri)
      # Only the presigned headers: API credentials must not go to storage.
      target.fetch("upload_headers", { "Content-Type" => content_type }).each { |k, v| request[k] = v }
      io.rewind if io.respond_to?(:rewind)
      request.body = io.read

      response = perform(uri, request)
      raise_for(response, "upload") unless response.is_a?(Net::HTTPSuccess)
      target.fetch("public_url")
    end

    # Submits a generation. Returns { "request_id", "status_url", "cancel_url", ... }.
    def submit(endpoint, body, idempotency_key:)
      post_json(endpoint, body, "Idempotency-Key" => idempotency_key)
    end

    def status(status_url)
      uri = URI(status_url)
      request = Net::HTTP::Get.new(uri)
      authorize(request)
      parse(perform(uri, request), "status")
    end

    private

    def post_json(path, body, headers = {})
      uri = URI.join(@base_url, path)
      request = Net::HTTP::Post.new(uri)
      authorize(request)
      request["Content-Type"] = "application/json"
      headers.each { |k, v| request[k] = v }
      request.body = body.to_json
      parse(perform(uri, request), path)
    end

    def authorize(request)
      raise ConfigurationError, "Defina HF_API_KEY no arquivo .env (formato <id>:<secret>)" unless configured?
      request["Authorization"] = "Key #{@credentials}"
      request["Accept"] = "application/json"
    end

    def perform(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
      raise TransientError, "Falha de rede ao falar com a Higgsfield: #{e.message}"
    end

    def parse(response, context)
      raise_for(response, context) unless response.is_a?(Net::HTTPSuccess)
      response.body.present? ? JSON.parse(response.body) : {}
    rescue JSON::ParserError
      raise RequestError.new("Resposta inválida da Higgsfield (#{context})", status: response.code.to_i, body: response.body)
    end

    def raise_for(response, context)
      code = response.code.to_i
      detail = error_detail(response.body)
      message = "Higgsfield respondeu #{code} em #{context}#{": #{detail}" if detail}"
      raise TransientError, message if code >= 500 || code == 429
      raise RequestError.new(message, status: code, body: response.body)
    end

    def error_detail(body)
      json = JSON.parse(body.to_s)
      detail = json["detail"] || json["error"] || json["message"]
      detail.is_a?(String) ? detail : detail&.to_json
    rescue JSON::ParserError
      body.to_s.truncate(200).presence
    end
  end
end
