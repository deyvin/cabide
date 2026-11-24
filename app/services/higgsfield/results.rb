require "net/http"

module Higgsfield
  # Shared by both backends: JPEG conversion of the original photo, downloading
  # finished outputs into Active Storage, and user-facing failure messages.
  module Results
    module_function

    def jpeg_bytes(photo)
      photo.original.variant(format: :jpeg, saver: { quality: 90 }, resize_to_limit: [ 3000, 3000 ]).processed.download
    end

    def attach(record, url)
      raise RequestError, "Geração concluída sem arquivo de saída" if url.blank?

      attachment, extension = record.is_a?(Video) ? [ record.file, "mp4" ] : [ record.catalog, "png" ]
      ext = File.extname(URI(url).path).delete(".").presence || extension
      attachment.attach(io: download(url), filename: "#{record.class.name.downcase}-#{record.id}.#{ext}")
      record.update!(status: "completed", error: nil)
    end

    def download(url, limit = 3)
      response = Net::HTTP.get_response(URI(url))
      return download(response["location"], limit - 1) if response.is_a?(Net::HTTPRedirection) && limit.positive?
      raise TransientError, "Falha ao baixar o resultado (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

      StringIO.new(response.body)
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
      raise TransientError, "Falha de rede ao baixar o resultado: #{e.message}"
    end

    def failure_message(status, error = nil)
      case status
      when "nsfw" then "A Higgsfield bloqueou o conteúdo (NSFW)."
      when "ip_detected" then "A Higgsfield bloqueou o conteúdo por direitos autorais."
      when "canceled" then "A geração foi cancelada."
      else "A geração falhou#{": #{error}" if error.present?}."
      end
    end
  end
end
