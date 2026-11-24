require "test_helper"

class Higgsfield::Mcp::GenerationTest < ActiveSupport::TestCase
  PRESIGNED = "https://upload.higgsfield.test/media.jpg"

  def session(extra = {})
    FakeMcpSession.new({
      "media_upload" => ->(args) { { "uploads" => [ { "upload_url" => PRESIGNED, "media_id" => "media-#{args[:files].first[:filename]}", "content_type" => args[:files].first[:content_type] } ] } },
      "media_confirm" => { "results" => [ { "status" => "uploaded" } ] },
      "generate_image_batch" => { "jobs" => [ { "index" => 0, "job_id" => "img-job", "status" => "pending" } ], "submitted_count" => 1 },
      "generate_video_batch" => { "jobs" => [ { "index" => 0, "job_id" => "vid-job", "status" => "pending" } ], "submitted_count" => 1 }
    }.merge(extra))
  end

  setup do
    stub_request(:put, PRESIGNED).with(headers: { "If-None-Match" => "*" }).to_return(status: 200)
  end

  test "submit_photo uploads a JPEG and asks Nano Banana for the catalog shot" do
    photo = create_garment(sides: %w[front back]).back
    fake = session
    Higgsfield::Mcp::Generation.new(session: fake).submit_photo(photo)

    assert_requested(:put, PRESIGNED) { |request| request.body.b.start_with?("\xFF\xD8".b) }
    assert_equal [ { "media_ids" => [ "media-photo-#{photo.id}.jpg" ], "type" => "image" } ], fake.args_for("media_confirm")

    params = fake.args_for("generate_image_batch").first.dig("requests", 0, "params")
    assert_equal "nano_banana_2_1", params["model"]
    assert_equal "3:4", params["aspect_ratio"]
    assert_equal false, params["use_unlim"]
    assert_includes params["prompt"], "back view"
    assert_equal [ { "value" => "media-photo-#{photo.id}.jpg", "role" => "image_references" } ], params["medias"]

    assert photo.reload.processing?
    assert_equal "img-job", photo.hf_request_id
    assert_equal "mcp", photo.hf_status_url
  end

  test "submit_video reuses MCP job ids as references and uploads the rest" do
    mcp_made = create_ready_garment(name: "Moletom")
    mcp_made.front.update!(hf_request_id: "catalog-job", hf_status_url: "mcp")
    api_made = create_ready_garment(name: "Calça")
    video = Video.create!(duration: 5, garments: [ mcp_made, api_made ])
    fake = session

    Higgsfield::Mcp::Generation.new(session: fake).submit_video(video)

    params = fake.args_for("generate_video_batch").first.dig("requests", 0, "params")
    assert_equal "kling4_0", params["model"]
    assert_equal "reference-to-video", params["mode"]
    assert_equal "9:16", params["aspect_ratio"]
    assert_equal 5, params["duration"]
    assert_equal [ "catalog-job", "media-catalog-#{api_made.front.id}.png" ], params["medias"].map { it["value"] }
    assert_includes params["prompt"], "Moletom and Calça"
    assert_equal "vid-job", video.reload.hf_request_id
  end

  test "regeneration notes are appended to the prompt with priority" do
    photo = create_garment.front
    photo.update!(instructions: "Mano Deyvin logo on the right chest")
    fake = session
    Higgsfield::Mcp::Generation.new(session: fake).submit_photo(photo)

    prompt = fake.args_for("generate_image_batch").first.dig("requests", 0, "params", "prompt")
    assert prompt.end_with?("highest priority, follow them exactly): Mano Deyvin logo on the right chest")
  end

  test "a rejected submission becomes a request error" do
    photo = create_garment.front
    fake = session("generate_image_batch" => { "jobs" => [], "failed_count" => 1, "errors" => [ { "error" => "insufficient credits" } ] })

    error = assert_raises(Higgsfield::RequestError) { Higgsfield::Mcp::Generation.new(session: fake).submit_photo(photo) }
    assert_match "insufficient credits", error.message
  end

  test "poll downloads the result when the job completes" do
    photo = create_garment.front
    photo.start_processing!(request_id: "img-job", status_url: "mcp")
    stub_request(:get, "https://cdn.higgsfield.test/out.png").to_return(body: file_fixture("catalog.png").read)
    fake = FakeMcpSession.new("jobs_wait" => { "jobs" => [ { "index" => 0, "job_id" => "img-job", "status" => "completed", "result_url" => "https://cdn.higgsfield.test/out.png" } ], "all_terminal" => true })

    assert_equal :done, Higgsfield::Mcp::Generation.new(session: fake).poll(photo)
    assert_equal [ { "jobs" => [ { "index" => 0, "job_id" => "img-job" } ], "timeout_seconds" => 0 } ], fake.args_for("jobs_wait")
    assert photo.reload.completed?
    assert photo.catalog.attached?
  end

  test "poll keeps waiting while the job is in progress" do
    photo = create_garment.front
    photo.start_processing!(request_id: "img-job", status_url: "mcp")
    fake = FakeMcpSession.new("jobs_wait" => { "jobs" => [ { "index" => 0, "job_id" => "img-job", "status" => "in_progress" } ], "all_terminal" => false })

    assert_equal :pending, Higgsfield::Mcp::Generation.new(session: fake).poll(photo)
    assert_equal 1, photo.reload.poll_attempts
  end

  test "poll fails blocked jobs with a readable message" do
    video = Video.create!(duration: 5, garments: [ create_ready_garment ])
    video.start_processing!(request_id: "vid-job", status_url: "mcp")
    fake = FakeMcpSession.new("jobs_wait" => { "jobs" => [ { "index" => 0, "job_id" => "vid-job", "status" => "ip_detected", "error" => "brand detected" } ] })

    assert_equal :done, Higgsfield::Mcp::Generation.new(session: fake).poll(video)
    assert video.reload.failed?
    assert_match "direitos autorais", video.error
  end
end
