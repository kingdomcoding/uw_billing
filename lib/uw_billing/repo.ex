defmodule UwBilling.Repo do
  use AshPostgres.Repo,
    otp_app: :uw_billing

  def installed_extensions do
    ["ash-functions", "citext", "uuid-ossp"]
  end

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end
