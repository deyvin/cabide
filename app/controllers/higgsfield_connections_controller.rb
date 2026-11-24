# Browser login to the Higgsfield MCP server (OAuth 2.1 + PKCE, dynamic client registration).
class HiggsfieldConnectionsController < ApplicationController
  # GET /higgsfield/connect
  def new
    redirect_to Higgsfield::Mcp::Session.new.authorization_url, allow_other_host: true
  rescue StandardError => e
    Rails.logger.error("[cabide] higgsfield connect failed: #{e.class}: #{e.message}")
    redirect_to root_path, alert: "Não foi possível iniciar o login na Higgsfield: #{e.message}"
  end

  # GET /higgsfield/callback
  def callback
    Higgsfield::Mcp::Session.new.finish_login(request.query_parameters)
    Rails.cache.delete(BalancesController::CACHE_KEY)
    redirect_to root_path, notice: "Higgsfield conectada. Pode gerar à vontade."
  rescue StandardError => e
    Rails.logger.error("[cabide] higgsfield callback failed: #{e.class}: #{e.message}")
    redirect_to root_path, alert: "O login na Higgsfield não foi concluído: #{e.message}"
  end

  # DELETE /higgsfield/connection
  def destroy
    HiggsfieldConnection.current.disconnect!
    Rails.cache.delete(BalancesController::CACHE_KEY)
    redirect_to root_path, notice: "Higgsfield desconectada."
  end
end
