class CreateVideoGarments < ActiveRecord::Migration[8.1]
  def change
    create_table :video_garments do |t|
      t.references :video, null: false, foreign_key: true
      t.references :garment, null: false, foreign_key: true

      t.timestamps
    end
  end
end
