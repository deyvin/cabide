class VideosController < ApplicationController
  def create
    garments = Garment.where(id: Array(params[:garment_ids])).includes(photos: [ catalog_attachment: :blob ])
    video = Video.new(duration: params[:duration].to_i.presence || 5, garments: garments.to_a)

    if video.save
      SubmitGenerationJob.perform_later(video)
      redirect_to root_path(anchor: "videos"), notice: "Vídeo em produção. Leva alguns minutos."
    else
      redirect_to root_path, alert: video.errors.full_messages.to_sentence
    end
  end

  def destroy
    Video.find(params[:id]).destroy
    redirect_to root_path(anchor: "videos"), notice: "Vídeo removido."
  end

  def retry
    video = Video.find(params[:id])
    video.regenerate!(instructions: video.instructions) if video.failed?
    redirect_to root_path(anchor: "videos")
  end

  # POST /videos/:id/regenerate — record it again, optionally with notes for the model.
  def regenerate
    video = Video.find(params[:id])
    if video.garments.all?(&:ready?) && video.regenerate!(instructions: params[:instructions])
      redirect_to root_path(anchor: "videos"), notice: "Gravando de novo. Leva alguns minutos."
    else
      redirect_to root_path(anchor: "videos"), alert: "Este vídeo não pode ser refeito agora (as peças precisam estar prontas)."
    end
  end
end
