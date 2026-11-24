require "test_helper"

class HiggsfieldConnectionFlowTest < ActionDispatch::IntegrationTest
  include SingletonStub

  class LoginSession
    attr_reader :finished_with

    def authorization_url = "https://clerk.higgsfield.test/oauth/authorize?state=abc"
    def finish_login(params) = (@finished_with = params)
  end

  test "the gallery asks to connect when the MCP backend has no login" do
    stub_singleton(Higgsfield, :backend, "mcp") do
      get root_path
    end
    assert_select "a[href='#{connect_higgsfield_path}']", /Conectar Higgsfield/
  end

  test "connected gallery shows the status and a lazy balance frame" do
    HiggsfieldConnection.current.save_tokens(access_token: "t")
    stub_singleton(Higgsfield, :backend, "mcp") do
      get root_path
    end
    assert_select "turbo-frame#balance[src='#{balance_path}']"
    assert_select "button", /Desconectar/
  end

  test "connect redirects the browser to the Higgsfield login" do
    stub_singleton(Higgsfield::Mcp::Session, :new, LoginSession.new) do
      get connect_higgsfield_path
    end
    assert_redirected_to "https://clerk.higgsfield.test/oauth/authorize?state=abc"
  end

  test "the callback hands the whole query to the OAuth flow" do
    login = LoginSession.new
    stub_singleton(Higgsfield::Mcp::Session, :new, login) do
      get higgsfield_callback_path, params: { code: "c0de", state: "abc", iss: "https://clerk.higgsfield.test" }
    end
    assert_redirected_to root_path
    assert_equal({ "code" => "c0de", "state" => "abc", "iss" => "https://clerk.higgsfield.test" }, login.finished_with.to_h)
    assert_match "conectada", flash[:notice]
  end

  test "balance renders the credits" do
    HiggsfieldConnection.current.save_tokens(access_token: "t")
    fake = FakeMcpSession.new("balance" => { "credits" => 2950.5, "subscription_plan_type" => "ultra" })
    stub_singleton(Higgsfield::Mcp::Session, :new, fake) do
      get balance_path
    end
    assert_response :success
    assert_select "turbo-frame#balance", /2\.950,5 créditos/
  end

  test "disconnect clears the tokens" do
    HiggsfieldConnection.current.save_tokens(access_token: "t")
    delete higgsfield_connection_path
    refute HiggsfieldConnection.current.connected?
  end
end
