require "test_helper"

class RegenerateFlowTest < ActionDispatch::IntegrationTest
  test "a completed photo can be regenerated with notes for the model" do
    garment = create_ready_garment(sides: %w[front back])
    photo = garment.front

    assert_enqueued_with(job: SubmitGenerationJob, args: [ photo ]) do
      post regenerate_photo_path(photo), params: { instructions: "  logo no peito direito " }
    end

    assert_redirected_to root_path
    photo.reload
    assert photo.pending?
    assert_equal "logo no peito direito", photo.instructions
    assert photo.catalog.attached?, "the previous catalog shot stays until the new one arrives"
    assert garment.back.reload.completed?, "only the chosen side is redone"
  end

  test "a photo already being generated is not submitted twice" do
    photo = create_garment.front
    photo.start_processing!(request_id: "r", status_url: "mcp")

    assert_no_enqueued_jobs(only: SubmitGenerationJob) { post regenerate_photo_path(photo) }
    assert_match "já está sendo gerada", flash[:alert]
  end

  test "a finished video can be recorded again" do
    video = Video.create!(duration: 5, garments: [ create_ready_garment ])
    video.update!(status: "completed")

    assert_enqueued_with(job: SubmitGenerationJob, args: [ video ]) do
      post regenerate_video_path(video), params: { instructions: "mostrar mais as costas" }
    end
    assert video.reload.pending?
    assert_equal "mostrar mais as costas", video.instructions
  end

  test "cards offer the regenerate action" do
    garment = create_ready_garment(sides: %w[front back])
    get root_path
    assert_select "button[data-action='regenerate#open'][data-regenerate-kind-param='photo']" do |buttons|
      options = JSON.parse(buttons.first["data-regenerate-options-param"])
      assert_equal %w[Frente Costas], options.map { it["label"] }
      assert_equal regenerate_photo_path(garment.front), options.first["url"]
    end
    assert_select "dialog#regenerate-dialog textarea[name=instructions]"
  end
end
