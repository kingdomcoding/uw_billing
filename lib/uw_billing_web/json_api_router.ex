defmodule UwBillingWeb.JsonApiRouter do
  use AshJsonApi.Router,
    domains: [UwBilling.Billing],
    json_schema: "/json_schema"
end
