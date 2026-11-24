class CreateGarments < ActiveRecord::Migration[8.1]
  def change
    create_table :garments do |t|
      t.string :name

      t.timestamps
    end
  end
end
