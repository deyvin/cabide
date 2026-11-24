module Higgsfield
  module Api
    # Backend that talks to the Higgsfield REST API (https://docs.higgsfield.ai)
    # with an API key. Select it with HF_BACKEND=api.
    class Generation
      TERMINAL_FAILURES = %w[failed nsfw canceled].freeze

      def initialize(client: Client.new, config: Client.config)
        @client = client
        @config = config
      end

      def ready?
        @client.configured?
      end

      # Converts the original photo to JPEG, uploads it and asks for the catalog version.
      def submit_photo(photo)
        url = @client.upload(StringIO.new(Results.jpeg_bytes(photo)), "image/jpeg")

        body = @config[:image][:params].to_h.merge(prompt: Prompts.catalog(photo.side, instructions: photo.instructions), image_urls: [ url ])
        request = @client.submit(@config[:image][:endpoint], body, idempotency_key: "cabide-photo-#{photo.id}-#{photo.updated_at.to_i}")
        photo.start_processing!(request_id: request.fetch("request_id"), status_url: status_url_for(request))
      end

      # Uploads the catalog images of the selected garments and asks for the UGC video.
      def submit_video(video)
        urls = video.reference_images.map do |image|
          image.open { |file| @client.upload(file, image.content_type) }
        end

        prompt = Prompts.ugc_video(garment_names: video.garments.map(&:display_name), instructions: video.instructions)
        body = @config[:video][:params].to_h.merge(prompt: prompt, image_urls: urls, duration: video.duration)
        request = @client.submit(@config[:video][:endpoint], body, idempotency_key: "cabide-video-#{video.id}-#{video.updated_at.to_i}")
        video.update!(prompt: prompt)
        video.start_processing!(request_id: request.fetch("request_id"), status_url: status_url_for(request))
      end

      # Checks one request. Returns :done or :pending.
      def poll(record)
        result = @client.status(record.hf_status_url)
        status = result["status"]

        if status == "completed"
          url = record.is_a?(Video) ? result.dig("video", "url") : result.dig("images", 0, "url")
          Results.attach(record, url)
          :done
        elsif TERMINAL_FAILURES.include?(status)
          record.fail!(Results.failure_message(status, result["error"]))
          :done
        else
          record.increment!(:poll_attempts)
          :pending
        end
      end

      private

      def status_url_for(request)
        request["status_url"].presence || URI.join(@config[:base_url], "/requests/#{request.fetch("request_id")}/status").to_s
      end
    end
  end
end
