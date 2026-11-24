# Credit balance pill in the header, loaded lazily in a Turbo Frame so a slow
# or failing MCP call never blocks the gallery.
class BalancesController < ApplicationController
  CACHE_KEY = "higgsfield/balance".freeze

  def show
    @balance = Rails.cache.fetch(CACHE_KEY, expires_in: 1.minute) do
      result = Higgsfield::Mcp::Session.new.call("balance")
      result.is_a?(Hash) ? result.slice("credits", "subscription_plan_type") : nil
    end
  rescue Higgsfield::Error => e
    Rails.logger.warn("[cabide] balance unavailable: #{e.message}")
    @balance = nil
  ensure
    render layout: false
  end
end
