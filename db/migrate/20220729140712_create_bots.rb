class CreateBots < ActiveRecord::Migration[7.0]
  def change
    create_table :bots do |t|
      t.string :name
      t.string :exchange
      t.string :key
      t.string :secret
      t.boolean :running

      t.timestamps
    end
  end
end
