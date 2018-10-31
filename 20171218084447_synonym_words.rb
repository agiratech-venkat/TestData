class SynonymWords < ActiveRecord::Migration
  def change
    create_table :synonyms do |t|
      t.string :word
      t.string :synonym

      t.timestamps
    end
  end
end
