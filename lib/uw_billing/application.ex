defmodule UwBilling.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ch_config = Application.get_env(:uw_billing, :clickhouse, [])

    ch_opts = [
      name: UwBilling.CH,
      hostname: ch_config[:hostname] || "localhost",
      port: ch_config[:port] || 8123,
      database: ch_config[:database] || "uw_billing",
      pool_size: ch_config[:pool_size] || 5
    ]

    ch_opts =
      if ch_config[:username], do: Keyword.put(ch_opts, :username, ch_config[:username]), else: ch_opts

    ch_opts =
      if ch_config[:password], do: Keyword.put(ch_opts, :password, ch_config[:password]), else: ch_opts

    children = [
      UwBillingWeb.Telemetry,
      UwBilling.Repo,
      {Ch, ch_opts},
      {DNSCluster, query: Application.get_env(:uw_billing, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: UwBilling.PubSub},
      UwBilling.Usage.BufferServer,
      {Oban, Application.fetch_env!(:uw_billing, Oban)},
      UwBillingWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: UwBilling.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)

    %{}
    |> UwBilling.Workers.CongressTradePoller.new()
    |> Oban.insert()

    {:ok, sup}
  end

  @impl true
  def config_change(changed, _new, removed) do
    UwBillingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
