defmodule UwBilling.Repo.Migrations.AddAppConfigs do
  use Ecto.Migration

  def up do
    create table(:app_configs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :singleton_key, :string, null: false
      add :uw_api_key, :string
      timestamps()
    end

    create unique_index(:app_configs, [:singleton_key],
             name: "app_configs_singleton_key_index")
  end

  def down do
    drop table(:app_configs)
  end
end
