require "test_helper"

class Higgsfield::ApiGenerationTest < ActiveSupport::TestCase
  IMAGE_ENDPOINT = "/xai/grok-imagine-image-2.0"
  VIDEO_ENDPOINT = "/kling-video/o3/image-reference"

  setup { @generation = Higgsfield::Api::Generation.new }

  test "submit_photo uploads a JPEG and sends the catalog prompt for the right side" do
    photo = create_garment(sides: %w[front back]).back
    url = stub_hf_upload
    stub_hf_submit(IMAGE_ENDPOINT, request_id: "photo-req")

    @generation.submit_photo(photo)

    assert_requested(:post, "#{HF}#{IMAGE_ENDPOINT}") do |request|
      body = JSON.parse(request.body)
      body["image_urls"] == [ url ] && body["prompt"].include?("back view") &&
        body["resolution"] == "2k" && body["quality"] == "medium"
    end
    assert photo.reload.processing?
    assert_equal "photo-req", photo.hf_request_id
    assert_equal "#{HF}/requests/photo-req/status", photo.hf_status_url
  end

  test "submit_photo converts HEIC uploads to JPEG" do
    garment = Garment.new(name: "iPhone")
    garment.photos.build(side: "front").original.attach(io: file_fixture("front.heic").open, filename: "front.heic", content_type: "image/heic")
    garment.save!
    stub_hf_upload
    stub_hf_submit(IMAGE_ENDPOINT)

    @generation.submit_photo(garment.front)

    assert_requested(:put, UPLOAD_URL) { |request| request.body.b.start_with?("\xFF\xD8".b) } # JPEG magic bytes
  end

  test "submit_video sends every catalog image of the look and the duration" do
    a = create_ready_garment(name: "Moletom", sides: %w[front back])
    b = create_ready_garment(name: "Calça")
    video = Video.create!(duration: 10, garments: [ a, b ])
    stub_hf_upload
    stub_hf_submit(VIDEO_ENDPOINT, request_id: "video-req")

    @generation.submit_video(video)

    assert_requested(:post, "#{HF}#{VIDEO_ENDPOINT}") do |request|
      body = JSON.parse(request.body)
      body["image_urls"].size == 3 && body["duration"] == 10 && body["aspect_ratio"] == "9:16" &&
        body["prompt"].include?("Moletom and Calça")
    end
    assert video.reload.processing?
    assert_includes video.prompt, "UGC"
  end

  test "poll attaches the catalog image when the request completes" do
    photo = create_garment.front
    photo.start_processing!(request_id: "r", status_url: "#{HF}/requests/r/status")
    stub_request(:get, "#{HF}/requests/r/status").to_return(json(status: "completed", images: [ { url: "https://cdn.higgsfield.test/out.png" } ]))
    stub_request(:get, "https://cdn.higgsfield.test/out.png").to_return(body: file_fixture("catalog.png").read)

    assert_equal :done, @generation.poll(photo)
    assert photo.reload.completed?
    assert photo.catalog.attached?
    assert photo.garment.ready?
  end

  test "poll attaches the video file" do
    video = Video.create!(duration: 5, garments: [ create_ready_garment ])
    video.start_processing!(request_id: "v", status_url: "#{HF}/requests/v/status")
    stub_request(:get, "#{HF}/requests/v/status").to_return(json(status: "completed", video: { url: "https://cdn.higgsfield.test/out.mp4" }))
    stub_request(:get, "https://cdn.higgsfield.test/out.mp4").to_return(body: "mp4-bytes")

    assert_equal :done, @generation.poll(video)
    assert video.reload.completed?
    assert_equal "mp4-bytes", video.file.download
  end

  test "poll keeps waiting while queued or in progress" do
    photo = create_garment.front
    photo.start_processing!(request_id: "r", status_url: "#{HF}/requests/r/status")
    stub_request(:get, "#{HF}/requests/r/status").to_return(json(status: "in_progress"))

    assert_equal :pending, @generation.poll(photo)
    assert_equal 1, photo.reload.poll_attempts
    assert photo.processing?
  end

  test "poll marks nsfw and failed requests as failed" do
    photo = create_garment.front
    photo.start_processing!(request_id: "r", status_url: "#{HF}/requests/r/status")
    stub_request(:get, "#{HF}/requests/r/status").to_return(json(status: "nsfw"))

    assert_equal :done, @generation.poll(photo)
    assert photo.reload.failed?
    assert_match "NSFW", photo.error
  end
end
