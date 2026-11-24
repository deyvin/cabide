class GarmentsController < ApplicationController
  def index
    @garments = Garment.newest_first.includes(photos: [ original_attachment: :blob, catalog_attachment: :blob ])
    @videos = Video.newest_first.includes(:garments, file_attachment: :blob)
    @higgsfield_ready = Higgsfield.generation.ready?
    @higgsfield_backend = Higgsfield.backend
  end

  def create
    @garment = Garment.new(name: garment_params[:name].presence)
    @garment.photos.build(side: "front", original: garment_params[:front])
    @garment.photos.build(side: "back", original: garment_params[:back]) if garment_params[:back].present?

    if @garment.save
      @garment.photos.each { SubmitGenerationJob.perform_later(it) }
      redirect_to root_path, notice: "Peça adicionada. A foto de catálogo fica pronta em instantes."
    else
      messages = @garment.photos.flat_map { it.errors[:base] }
      redirect_to root_path, alert: messages.to_sentence.presence || "Não foi possível salvar a peça."
    end
  end

  def destroy
    Garment.find(params[:id]).destroy
    redirect_to root_path, notice: "Peça removida."
  end

  def retry
    garment = Garment.find(params[:id])
    garment.photos.select(&:failed?).each do |photo|
      photo.reset_for_retry!
      SubmitGenerationJob.perform_later(photo)
    end
    redirect_to root_path
  end

  private

  def garment_params
    params.expect(garment: %i[name front back])
  end
end
