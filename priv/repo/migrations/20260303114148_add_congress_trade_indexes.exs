defmodule UwBilling.Repo.Migrations.AddCongressTradeIndexes do
  use Ecto.Migration

  def up do
    create index(:congress_trades, [:ticker])
    create index(:congress_trades, [:filed_at])
    create index(:congress_trades, [:traded_at])

    execute(
      """
      CREATE OR REPLACE FUNCTION protect_amount_range()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.amount_range IS NULL AND OLD.amount_range IS NOT NULL THEN
          NEW.amount_range := OLD.amount_range;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS protect_amount_range();"
    )

    execute(
      """
      CREATE TRIGGER congress_trades_protect_amount_range
        BEFORE UPDATE ON congress_trades
        FOR EACH ROW EXECUTE FUNCTION protect_amount_range();
      """,
      "DROP TRIGGER IF EXISTS congress_trades_protect_amount_range ON congress_trades;"
    )
  end

  def down do
    execute("DROP TRIGGER IF EXISTS congress_trades_protect_amount_range ON congress_trades;")
    execute("DROP FUNCTION IF EXISTS protect_amount_range();")

    drop index(:congress_trades, [:traded_at])
    drop index(:congress_trades, [:filed_at])
    drop index(:congress_trades, [:ticker])
  end
end
