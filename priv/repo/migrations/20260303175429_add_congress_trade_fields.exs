defmodule UwBilling.Repo.Migrations.AddCongressTradeFields do
  use Ecto.Migration

  def up do
    alter table(:congress_trades) do
      add :politician_id, :text, null: true
      add :issuer,        :text, null: true
      add :member_type,   :text, null: true
    end

    execute """
    CREATE OR REPLACE FUNCTION protect_amount_range()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.amount_range IS NULL AND OLD.amount_range IS NOT NULL THEN
        NEW.amount_range := OLD.amount_range;
      END IF;
      IF NEW.politician_id IS NULL AND OLD.politician_id IS NOT NULL THEN
        NEW.politician_id := OLD.politician_id;
      END IF;
      IF NEW.issuer IS NULL AND OLD.issuer IS NOT NULL THEN
        NEW.issuer := OLD.issuer;
      END IF;
      IF NEW.member_type IS NULL AND OLD.member_type IS NOT NULL THEN
        NEW.member_type := OLD.member_type;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  def down do
    alter table(:congress_trades) do
      remove :politician_id
      remove :issuer
      remove :member_type
    end

    execute """
    CREATE OR REPLACE FUNCTION protect_amount_range()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.amount_range IS NULL AND OLD.amount_range IS NOT NULL THEN
        NEW.amount_range := OLD.amount_range;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end
end
