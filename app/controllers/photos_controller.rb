class PhotosController < ApplicationController
  # POST /photos/:id/regenerate — redo one catalog photo, optionally with notes
  # for the model ("o logo Mano Deyvin fica no peito direito").
  def regenerate
    photo = Photo.find(params[:id])
    if photo.regenerate!(instructions: params[:instructions])
      redirect_to root_path, notice: "Refazendo a foto da #{photo.side_label} de #{photo.garment.display_name}."
    else
      redirect_to root_path, alert: "Essa foto já está sendo gerada."
    end
  end
end
