require "test_helper"

class CabideFlowTest < ActionDispatch::IntegrationTest
  test "gallery renders empty and with garments" do
    get root_path
    assert_response :success
    assert_select "h1", /Cabide/

    create_ready_garment(name: "Moletom")
    get root_path
    assert_select "article h3", "Moletom"
    assert_select "button[data-action='selection#toggle']", 1
  end

  test "adding a garment with front and back queues one catalog job per photo" do
    assert_difference -> { Photo.count }, 2 do
      assert_enqueued_jobs 2, only: SubmitGenerationJob do
        post garments_path, params: { garment: {
          name: "Moletom",
          front: fixture_upload("front.heic", "application/octet-stream"),
          back: fixture_upload("front.jpg", "image/jpeg")
        } }
      end
    end
    assert_redirected_to root_path
    assert_equal %w[front back], Garment.last.photos.map(&:side)
  end

  test "a non-image upload is rejected" do
    assert_no_difference -> { Garment.count } do
      post garments_path, params: { garment: { front: Rack::Test::UploadedFile.new(StringIO.new("x"), "text/plain", original_filename: "notes.txt") } }
    end
    assert_match "precisa ser uma imagem", flash[:alert]
  end

  test "a video needs ready garments" do
    pending_garment = create_garment

    assert_no_difference -> { Video.count } do
      post videos_path, params: { garment_ids: [ pending_garment.id ], duration: 5 }
    end
    assert_match "prontas", flash[:alert]
  end

  test "a video from selected garments is queued" do
    a = create_ready_garment(sides: %w[front back])
    b = create_ready_garment

    assert_enqueued_with(job: SubmitGenerationJob) do
      post videos_path, params: { garment_ids: [ a.id, b.id ], duration: 10 }
    end
    video = Video.last
    assert_equal [ a, b ].sort, video.garments.sort
    assert_equal 10, video.duration
  end

  test "a video cannot exceed the reference image limit" do
    ids = 4.times.map { create_ready_garment(sides: %w[front back]).id } # 8 images

    assert_no_difference -> { Video.count } do
      post videos_path, params: { garment_ids: ids }
    end
    assert_match "Máximo", flash[:alert]
  end

  test "retry resubmits only the failed photos" do
    garment = create_garment(sides: %w[front back])
    garment.front.fail!("boom")

    assert_enqueued_jobs 1, only: SubmitGenerationJob do
      post retry_garment_path(garment)
    end
    assert garment.front.reload.pending?
  end
end
