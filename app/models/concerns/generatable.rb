# Shared state for anything produced by a Higgsfield generation request
# (catalog photos and UGC videos): status, request tracking and polling.
module Generatable
  extend ActiveSupport::Concern

  STATUSES = %w[pending processing completed failed].freeze

  included do
    validates :status, inclusion: { in: STATUSES }

    STATUSES.each do |name|
      define_method(:"#{name}?") { status == name }
    end
  end

  def in_flight?
    pending? || processing?
  end

  def start_processing!(request_id:, status_url:)
    update!(status: "processing", hf_request_id: request_id, hf_status_url: status_url, error: nil, poll_attempts: 0)
  end

  def fail!(message)
    update!(status: "failed", error: message.to_s.truncate(500))
  end

  def reset_for_retry!
    update!(status: "pending", hf_request_id: nil, hf_status_url: nil, error: nil, poll_attempts: 0)
  end

  # Generate again (after a bad result or a failure), optionally with extra
  # instructions for the model. The previous output stays visible until the new one lands.
  def regenerate!(instructions: nil)
    return false if in_flight?

    update!(instructions: instructions.to_s.strip.presence)
    reset_for_retry!
    SubmitGenerationJob.perform_later(self)
    true
  end
end
