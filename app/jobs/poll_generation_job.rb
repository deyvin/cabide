# Polls a Higgsfield request until it finishes, re-enqueueing itself in between.
class PollGenerationJob < ApplicationJob
  queue_as :default

  retry_on Higgsfield::TransientError, wait: :polynomially_longer, attempts: 8 do |job, error|
    job.arguments.first.fail!(error.message)
  end

  discard_on ActiveRecord::RecordNotFound, ActiveJob::DeserializationError

  def perform(record)
    return unless record.processing?

    config = Higgsfield::Client.config
    if record.poll_attempts >= config[:max_poll_attempts].to_i
      record.fail!("A Higgsfield demorou demais para responder. Tente de novo.")
      return
    end

    if Higgsfield.generation.poll(record) == :pending
      self.class.set(wait: config[:poll_interval].to_i.seconds).perform_later(record)
    end
  rescue Higgsfield::RequestError, Higgsfield::ConfigurationError => e
    Rails.logger.error("[cabide] poll #{record.class}##{record.id} failed: #{e.message}")
    record.fail!(e.message)
  end
end
