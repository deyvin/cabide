# Sends a photo (catalog image) or a video (UGC) to Higgsfield, then starts polling.
class SubmitGenerationJob < ApplicationJob
  queue_as :default

  retry_on Higgsfield::TransientError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first.fail!(error.message)
  end

  discard_on ActiveRecord::RecordNotFound, ActiveJob::DeserializationError

  def perform(record)
    return unless record.pending?

    generation = Higgsfield.generation
    case record
    when Photo then generation.submit_photo(record)
    when Video then generation.submit_video(record)
    else raise ArgumentError, "Unsupported record: #{record.class}"
    end

    PollGenerationJob.set(wait: poll_interval).perform_later(record)
  rescue Higgsfield::TransientError
    raise # handled by retry_on
  rescue StandardError => e
    # Bad requests, missing credentials, unreadable images: retrying won't help.
    Rails.logger.error("[cabide] submit #{record.class}##{record.id} failed: #{e.message}")
    record.fail!(e.message)
  end

  private

  def poll_interval
    Higgsfield::Client.config[:poll_interval].to_i.seconds
  end
end
