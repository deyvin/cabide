ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { require it }

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    include ActiveJob::TestHelper

    HF = "https://api.higgsfield.test"
    UPLOAD_URL = "https://storage.higgsfield.test/presigned"

    def fixture_upload(name, content_type)
      Rack::Test::UploadedFile.new(file_fixture(name), content_type)
    end

    def create_garment(name: "Moletom", sides: %w[front], status: "pending", catalog: false)
      garment = Garment.new(name: name)
      sides.each do |side|
        photo = garment.photos.build(side: side, status: status)
        photo.original.attach(io: file_fixture("front.jpg").open, filename: "#{side}.jpg", content_type: "image/jpeg")
      end
      garment.save!
      if catalog
        garment.photos.each do |photo|
          photo.catalog.attach(io: file_fixture("catalog.png").open, filename: "catalog-#{photo.id}.png", content_type: "image/png")
        end
      end
      garment.reload
    end

    def create_ready_garment(**options)
      create_garment(status: "completed", catalog: true, **options)
    end

    # Stubs the two-step upload (presigned URL + PUT) and returns the public URL.
    def stub_hf_upload(public_url: "https://cdn.higgsfield.test/input.jpg")
      stub_request(:post, "#{HF}/files/generate-upload-url").to_return(json(
        public_url: public_url, upload_url: UPLOAD_URL,
        upload_headers: { "Content-Type" => "image/jpeg", "x-amz-tagging" => "retention=temporary" }
      ))
      stub_request(:put, UPLOAD_URL).to_return(status: 200)
      public_url
    end

    def stub_hf_submit(endpoint, request_id: "req-1")
      stub_request(:post, "#{HF}#{endpoint}").to_return(json(
        request_id: request_id,
        status_url: "#{HF}/requests/#{request_id}/status",
        cancel_url: "#{HF}/requests/#{request_id}/cancel",
        status: "queued"
      ))
    end

    def json(body = nil, http_status: 200, **attrs)
      { status: http_status, body: (body || attrs).to_json, headers: { "Content-Type" => "application/json" } }
    end
  end
end
