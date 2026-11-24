class AddInstructionsToPhotosAndVideos < ActiveRecord::Migration[8.1]
  def change
    # Optional user notes appended to the prompt when regenerating ("logo on the chest").
    add_column :photos, :instructions, :text
    add_column :videos, :instructions, :text
  end
end
