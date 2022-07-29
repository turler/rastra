class CreatePairs < ActiveRecord::Migration[7.0]
  def change
    create_table :pairs do |t|
      t.string :name

      t.timestamps
    end
  end
end
