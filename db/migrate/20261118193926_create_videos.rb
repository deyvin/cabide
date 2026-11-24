class CreateVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :videos do |t|
      t.string :status, null: false, default: "pending"
      t.integer :duration, null: false, default: 5
      t.text :prompt
      t.string :hf_request_id
      t.string :hf_status_url
      t.text :error

      t.integer :poll_attempts, null: false, default: 0

      t.timestamps
    end
  end
end
