defmodule UwBilling.Repo.Migrations.AddUserProvidedToStripeConfigs do
  use Ecto.Migration

  def change do
    alter table(:stripe_configs) do
      add :user_provided, :boolean, default: false, null: false
    end
  end
end
