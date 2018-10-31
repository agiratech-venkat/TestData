class ChangeSynonymWordType < ActiveRecord::Migration
  def up
    change_column :synonyms, :synonym, :text, array: true, default: [], using: "(string_to_array(synonym, ','))"
  end
  def down
    change_column :synonyms, :synonym, :text, array: false, default: nil, using: "(string_to_array(synonym, ','))"
  end
end
