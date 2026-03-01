defmodule UwBilling.Repo do
  use Ecto.Repo,
    otp_app: :uw_billing,
    adapter: Ecto.Adapters.Postgres
end
