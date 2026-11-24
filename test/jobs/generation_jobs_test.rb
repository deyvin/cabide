require "test_helper"

class GenerationJobsTest < ActiveSupport::TestCase
  test "submit job sends the photo and schedules polling" do
    photo = create_garment.front
    stub_hf_upload
    stub_hf_submit("/xai/grok-imagine-image-2.0")

    assert_enqueued_with(job: PollGenerationJob, args: [ photo ]) do
      SubmitGenerationJob.perform_now(photo)
    end
    assert photo.reload.processing?
  end

  test "submit job marks the record failed on a permanent API error" do
    photo = create_garment.front
    stub_hf_upload
    stub_request(:post, "#{HF}/xai/grok-imagine-image-2.0").to_return(json({ detail: "Not enough credits" }, http_status: 402))

    assert_no_enqueued_jobs(only: PollGenerationJob) { SubmitGenerationJob.perform_now(photo) }
    assert photo.reload.failed?
    assert_match "Not enough credits", photo.error
  end

  test "submit job retries transient errors" do
    photo = create_garment.front
    stub_request(:post, "#{HF}/files/generate-upload-url").to_return(status: 502)

    assert_enqueued_with(job: SubmitGenerationJob) { SubmitGenerationJob.perform_now(photo) }
    assert photo.reload.pending?
  end

  test "poll job re-enqueues itself until the request finishes" do
    photo = create_garment.front
    photo.start_processing!(request_id: "r", status_url: "#{HF}/requests/r/status")
    stub_request(:get, "#{HF}/requests/r/status").to_return(json(status: "queued"))

    assert_enqueued_with(job: PollGenerationJob, args: [ photo ]) { PollGenerationJob.perform_now(photo) }
  end

  test "poll job gives up after the maximum number of attempts" do
    photo = create_garment.front
    photo.start_processing!(request_id: "r", status_url: "#{HF}/requests/r/status")
    photo.update!(poll_attempts: Higgsfield::Client.config[:max_poll_attempts])

    assert_no_enqueued_jobs(only: PollGenerationJob) { PollGenerationJob.perform_now(photo) }
    assert photo.reload.failed?
  end
end
