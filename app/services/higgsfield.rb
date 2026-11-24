# Higgsfield integration. Two interchangeable backends share one interface
# (ready?, submit_photo, submit_video, poll):
#   - Mcp::Generation: the official MCP server (OAuth, subscription credits) — default
#   - Api::Generation: the REST API (API key, prepaid balance)
module Higgsfield
  BACKENDS = %w[mcp api].freeze

  def self.backend
    Client.config[:backend].to_s.presence_in(BACKENDS) || "mcp"
  end

  def self.generation
    backend == "api" ? Api::Generation.new : Mcp::Generation.new
  end

  class Error < StandardError; end
  class ConfigurationError < Error; end
  # 4xx and other responses that retrying will not fix.
  class RequestError < Error
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end
  # Network failures and 5xx: safe to retry.
  class TransientError < Error; end
end
