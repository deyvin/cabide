class Photo < ApplicationRecord
  include Generatable

  SIDES = %w[front back].freeze
  CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze

  belongs_to :garment

  has_one_attached :original
  has_one_attached :catalog

  validates :side, inclusion: { in: SIDES }, uniqueness: { scope: :garment_id }
  validate :original_is_an_image

  after_update_commit -> { garment.broadcast_replace_later_to :garments }

  def front? = side == "front"
  def back? = side == "back"

  def side_label
    front? ? "frente" : "costas"
  end

  private

  def original_is_an_image
    if !original.attached?
      errors.add(:base, "A foto da #{side_label} é obrigatória")
    elsif !CONTENT_TYPES.include?(original.content_type) && !heic_by_name?
      errors.add(:base, "A foto da #{side_label} precisa ser uma imagem (JPG, PNG, WEBP ou HEIC)")
    end
  end

  # Browsers often upload HEIC as application/octet-stream.
  def heic_by_name?
    original.filename.extension.to_s.downcase.in?(%w[heic heif])
  end
end
