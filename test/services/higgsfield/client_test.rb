require "test_helper"

class Higgsfield::ClientTest < ActiveSupport::TestCase
  setup { @client = Higgsfield::Client.new }

  test "submit sends key auth, JSON body and idempotency key" do
    stub = stub_request(:post, "#{HF}/xai/grok-imagine-image-2.0")
      .with(
        headers: { "Authorization" => "Key test-key:test-secret", "Idempotency-Key" => "abc", "Content-Type" => "application/json" },
        body: { prompt: "hi", image_urls: [ "u" ] }.to_json
      )
      .to_return(json(request_id: "r1", status_url: "#{HF}/requests/r1/status"))

    result = @client.submit("/xai/grok-imagine-image-2.0", { prompt: "hi", image_urls: [ "u" ] }, idempotency_key: "abc")

    assert_requested stub
    assert_equal "r1", result["request_id"]
  end

  test "upload asks for a presigned URL and PUTs the bytes without API credentials" do
    public_url = stub_hf_upload
    @client.upload(StringIO.new("jpeg-bytes"), "image/jpeg").then { assert_equal public_url, it }

    assert_requested :post, "#{HF}/files/generate-upload-url", body: { content_type: "image/jpeg" }.to_json
    assert_requested(:put, UPLOAD_URL, body: "jpeg-bytes") do |request|
      request.headers["X-Amz-Tagging"] == "retention=temporary" && request.headers["Authorization"].nil?
    end
  end

  test "status reads the status URL" do
    stub_request(:get, "#{HF}/requests/r1/status").to_return(json(status: "in_progress"))
    assert_equal "in_progress", @client.status("#{HF}/requests/r1/status")["status"]
  end

  test "5xx and 429 are transient" do
    stub_request(:get, "#{HF}/requests/r1/status").to_return(status: 503, body: "down")
    assert_raises(Higgsfield::TransientError) { @client.status("#{HF}/requests/r1/status") }

    stub_request(:get, "#{HF}/requests/r2/status").to_return(status: 429, body: "")
    assert_raises(Higgsfield::TransientError) { @client.status("#{HF}/requests/r2/status") }
  end

  test "4xx raises a request error with the API detail" do
    stub_request(:post, "#{HF}/x").to_return(json({ detail: "Not enough credits" }, http_status: 402))
    error = assert_raises(Higgsfield::RequestError) { @client.submit("/x", {}, idempotency_key: "k") }
    assert_equal 402, error.status
    assert_match "Not enough credits", error.message
  end

  test "accepts the single id:secret key from the console" do
    client = Higgsfield::Client.new(Higgsfield::Client.config.merge(api_key: "abc:xyz", key_id: nil, key_secret: nil))
    stub = stub_request(:get, "#{HF}/requests/r1/status").with(headers: { "Authorization" => "Key abc:xyz" }).to_return(json(status: "queued"))
    client.status("#{HF}/requests/r1/status")
    assert_requested stub
  end

  test "network failures are transient" do
    stub_request(:get, "#{HF}/requests/r1/status").to_timeout
    assert_raises(Higgsfield::TransientError) { @client.status("#{HF}/requests/r1/status") }
  end

  test "missing credentials raise a configuration error before any request" do
    client = Higgsfield::Client.new(Higgsfield::Client.config.merge(api_key: nil, key_id: nil))
    refute client.configured?
    assert_raises(Higgsfield::ConfigurationError) { client.submit("/x", {}, idempotency_key: "k") }
  end
end
