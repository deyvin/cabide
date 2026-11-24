class Garment < ApplicationRecord
  has_many :photos, -> { order(Arel.sql("CASE side WHEN 'front' THEN 0 ELSE 1 END")) }, dependent: :destroy
  has_many :video_garments, dependent: :destroy
  has_many :videos, through: :video_garments

  scope :newest_first, -> { order(created_at: :desc) }

  after_create_commit -> { broadcast_prepend_later_to :garments, target: "garments" }
  after_update_commit -> { broadcast_replace_later_to :garments }
  after_destroy_commit -> { broadcast_remove_to :garments }

  def front = photos.detect { it.side == "front" }
  def back = photos.detect { it.side == "back" }

  def display_name
    name.presence || "Peça ##{id}"
  end

  # A garment can go into a video once every photo has its catalog version.
  def ready?
    photos.any? && photos.all?(&:completed?)
  end

  def processing?
    photos.any?(&:in_flight?)
  end

  def failed?
    photos.any?(&:failed?)
  end

  # Catalog images used as references for video generation (front first).
  def catalog_images
    photos.select(&:completed?).map(&:catalog).select(&:attached?)
  end
end
