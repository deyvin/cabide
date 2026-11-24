require "test_helper"

# Drives the real `mcp` gem OAuth code against stubbed Higgsfield endpoints:
# protected-resource metadata, the Clerk authorization server and the MCP server.
class Higgsfield::Mcp::SessionTest < ActiveSupport::TestCase
  MCP_URL = "https://mcp.higgsfield.test/mcp".freeze
  PRM_URL = "https://mcp.higgsfield.test/.well-known/oauth-protected-resource/mcp".freeze
  ISSUER = "https://higgsfield.test/_clerk".freeze
  OLD_ISSUER = "https://clerk.higgsfield.test".freeze
  TOKEN_URL = "#{ISSUER}/oauth/token".freeze
  CONFIG = { url: MCP_URL, redirect_uri: "http://localhost:3000/higgsfield/callback" }.freeze

  setup do
    @accepted_tokens = []
    stub_request(:get, PRM_URL).to_return(json(
      resource: MCP_URL, authorization_servers: [ ISSUER ], scopes_supported: %w[openid email offline_access]
    ))
    stub_request(:get, "https://higgsfield.test/.well-known/oauth-authorization-server/_clerk").to_return(json(
      issuer: ISSUER,
      authorization_endpoint: "#{ISSUER}/oauth/authorize",
      token_endpoint: TOKEN_URL,
      registration_endpoint: "#{ISSUER}/oauth/register",
      response_types_supported: %w[code],
      grant_types_supported: %w[authorization_code refresh_token],
      token_endpoint_auth_methods_supported: %w[none client_secret_basic],
      code_challenge_methods_supported: %w[S256],
      scopes_supported: %w[openid email offline_access],
      authorization_response_iss_parameter_supported: true
    ))
    stub_mcp_server

    @connection = HiggsfieldConnection.current
    @connection.save_client_information(client_id: "client-1", token_endpoint_auth_method: "none", issuer: ISSUER)
  end

  test "renews an expired access token before calling, and stores the rotated tokens" do
    connect(access_token: "old-access", refresh_token: "refresh-1", expires_in: 3600)
    stub_token_endpoint(access_token: "new-access", refresh_token: "refresh-2")

    result = travel(2.hours) { session.call("balance") }

    assert_equal({ "credits" => 2950.5 }, result)
    assert_requested(:post, TOKEN_URL) { |request| form(request).values_at("grant_type", "refresh_token", "client_id") == %w[refresh_token refresh-1 client-1] }
    @connection.reload
    assert_equal "new-access", @connection.tokens["access_token"]
    assert_equal "refresh-2", @connection.refresh_token
    assert_equal ISSUER, @connection.tokens["issuer"]
    refute_requested(:post, MCP_URL, headers: { "Authorization" => "Bearer old-access" })
  end

  test "a 401 on a token without known expiry is renewed by the gem and retried" do
    connect(access_token: "revoked-access", refresh_token: "refresh-1") # saved before expires_at was tracked
    stub_token_endpoint(access_token: "new-access", refresh_token: "refresh-2")

    assert_equal({ "credits" => 2950.5 }, session.call("balance"))
    assert_equal "refresh-2", @connection.reload.refresh_token
  end

  test "when Higgsfield moves its authorization server, asks to reconnect and says why (the 2026-11-24 outage)" do
    connect(access_token: "old-access", refresh_token: "refresh-1", expires_in: 3600, issuer: OLD_ISSUER)
    @connection.save_client_information(client_id: "client-1", token_endpoint_auth_method: "none", issuer: OLD_ISSUER)

    error = assert_raises(Higgsfield::ConfigurationError) { travel(2.hours) { session.call("balance") } }

    assert_match "expirou", error.message
    assert_match "different authorization server", error.message
    refute @connection.reload.connected?
    assert_not_requested(:post, TOKEN_URL)
  end

  test "a revoked refresh token disconnects" do
    connect(access_token: "old-access", refresh_token: "refresh-1", expires_in: 3600)
    stub_request(:post, TOKEN_URL).to_return(json({ error: "invalid_grant" }, http_status: 400))

    assert_raises(Higgsfield::ConfigurationError) { travel(2.hours) { session.call("balance") } }
    refute @connection.reload.connected?
  end

  test "a transient refresh failure keeps the refresh token for the next attempt" do
    connect(access_token: "old-access", refresh_token: "refresh-1", expires_in: 3600)
    stub_request(:post, TOKEN_URL).to_return(status: 503).then.to_return(json(access_token: "new-access", refresh_token: "refresh-2", expires_in: 3600))

    travel 2.hours do
      assert_raises(Higgsfield::TransientError) { session.call("balance") }
      assert @connection.reload.connected?
      assert_equal "refresh-1", @connection.refresh_token

      @accepted_tokens << "new-access"
      assert_equal({ "credits" => 2950.5 }, session.call("balance"))
    end
  end

  test "when the gem gives up on a 401 after a transient failure, the login is kept" do
    connect(access_token: "revoked-access", refresh_token: "refresh-1")
    stub_request(:post, TOKEN_URL).to_return(status: 500)

    assert_raises(Higgsfield::TransientError) { session.call("balance") }
    @connection.reload
    assert @connection.connected?
    assert_equal "refresh-1", @connection.refresh_token
    assert_nil @connection.pending
    assert_equal "client-1", @connection.client_information["client_id"]
  end

  test "losing a refresh race to another process is not a logout" do
    connect(access_token: "old-access", refresh_token: "refresh-1", expires_in: 3600)
    stub_request(:post, TOKEN_URL).to_return do
      # Another worker redeemed refresh-1 a moment earlier; Clerk rotated it.
      HiggsfieldConnection.find(@connection.id).save_tokens(access_token: "their-access", refresh_token: "refresh-2", expires_in: 3600)
      json({ error: "invalid_grant" }, http_status: 400)
    end
    @accepted_tokens << "their-access"

    assert_equal({ "credits" => 2950.5 }, travel(2.hours) { session(HiggsfieldConnection.find(@connection.id)).call("balance") })
    assert_equal "refresh-2", @connection.reload.refresh_token
  end

  private

  def session(connection = @connection)
    Higgsfield::Mcp::Session.new(connection: connection, config: CONFIG)
  end

  def connect(issuer: ISSUER, **tokens)
    @connection.save_tokens(tokens.merge(token_type: "Bearer", scope: "openid email offline_access", issuer: issuer))
    @accepted_tokens << tokens[:access_token] unless tokens[:access_token].start_with?("old", "revoked")
  end

  def stub_token_endpoint(access_token:, refresh_token:)
    @accepted_tokens << access_token
    stub_request(:post, TOKEN_URL).to_return(json(
      access_token: access_token, refresh_token: refresh_token, expires_in: 3600, token_type: "Bearer", scope: "openid email offline_access"
    ))
  end

  def form(request) = Rack::Utils.parse_query(request.body)

  def stub_mcp_server
    stub_request(:post, MCP_URL).to_return do |request|
      bearer = request.headers["Authorization"].to_s.delete_prefix("Bearer ")
      next { status: 401, headers: { "WWW-Authenticate" => %(Bearer resource_metadata="#{PRM_URL}", scope="openid email offline_access") } } unless @accepted_tokens.include?(bearer)

      message = JSON.parse(request.body)
      case message["method"]
      when "initialize"
        json(jsonrpc: "2.0", id: message["id"], result: {
          protocolVersion: message.dig("params", "protocolVersion"), capabilities: { tools: {} }, serverInfo: { name: "higgsfield", version: "1" }
        })
      when "tools/call"
        json(jsonrpc: "2.0", id: message["id"], result: {
          content: [ { type: "text", text: { credits: 2950.5 }.to_json } ], structuredContent: { credits: 2950.5 }
        })
      else
        { status: 202 }
      end
    end
  end
end
