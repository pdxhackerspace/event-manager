class AddAiConnectionSettingsToSiteConfigs < ActiveRecord::Migration[8.1]
  def change
    change_table :site_configs, bulk: true do |t|
      t.string :ai_url
      t.text :ai_key
    end
  end
end
