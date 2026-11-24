class Video < ApplicationRecord
  include Generatable

  DURATIONS = [ 5, 10 ].freeze
  def self.max_reference_images
    Higgsfield.backend == "mcp" ? Higgsfield::Client.config.dig(:mcp, :video, :max_reference_images).to_i : 7
  end

  has_many :video_garments, dependent: :destroy
  has_many :garments, through: :video_garments

  has_one_attached :file

  validates :duration, inclusion: { in: DURATIONS }
  validate :has_garments_within_limit, on: :create

  scope :newest_first, -> { order(created_at: :desc) }

  after_create_commit -> { broadcast_prepend_later_to :videos, target: "videos" }
  after_update_commit -> { broadcast_replace_later_to :videos }
  after_destroy_commit -> { broadcast_remove_to :videos }

  def reference_images
    garments.flat_map(&:catalog_images)
  end

  private

  def has_garments_within_limit
    if garments.empty?
      errors.add(:base, "Selecione pelo menos uma peça")
    elsif garments.any? { !it.ready? }
      errors.add(:base, "Todas as peças precisam estar prontas")
    elsif garments.sum { it.catalog_images.size } > self.class.max_reference_images
      errors.add(:base, "Máximo de #{self.class.max_reference_images} fotos por vídeo — selecione menos peças")
    end
  end
end
