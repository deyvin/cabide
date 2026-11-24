class CreatePhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :photos do |t|
      t.references :garment, null: false, foreign_key: true
      t.string :side, null: false, default: "front"
      t.string :status, null: false, default: "pending"
      t.string :hf_request_id
      t.string :hf_status_url
      t.text :error

      t.integer :poll_attempts, null: false, default: 0

      t.timestamps
    end
    add_index :photos, [ :garment_id, :side ], unique: true
  end
end
