defmodule UwBilling.Usage.BufferServer do
  use GenServer

  @flush_interval 1_000
  @flush_threshold 500

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def push(event) do
    GenServer.cast(__MODULE__, {:push, event})
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    timer = schedule_flush()
    {:ok, {[], timer}}
  end

  @impl true
  def handle_cast({:push, event}, {buffer, timer}) do
    buffer = [event | buffer]

    if length(buffer) >= @flush_threshold do
      cancel_timer(timer)
      flush(buffer)
      {:noreply, {[], schedule_flush()}}
    else
      {:noreply, {buffer, timer}}
    end
  end

  @impl true
  def handle_info(:flush, {buffer, _timer}) do
    if buffer != [], do: flush(buffer)
    {:noreply, {[], schedule_flush()}}
  end

  @impl true
  def terminate(_reason, {buffer, _timer}) do
    if buffer != [], do: flush(buffer)
    :ok
  end

  defp flush(buffer) do
    events = Enum.reverse(buffer)
    rows = Enum.map(events, &event_to_row/1)

    query = """
    INSERT INTO uw_billing.api_requests
    (user_id, plan_tier, method, path, status_code, duration_ms, error, timestamp)
    VALUES
    """

    case Ch.query(UwBilling.CH, query, rows, types: [
      "UInt64", "LowCardinality(String)", "LowCardinality(String)",
      "LowCardinality(String)", "UInt16", "Float32", "UInt8", "DateTime"
    ]) do
      {:ok, _} -> :ok
      {:error, reason} -> require Logger; Logger.warning("BufferServer flush failed: #{inspect(reason)}")
    end
  rescue
    e -> require Logger; Logger.warning("BufferServer flush exception: #{inspect(e)}")
  end

  defp event_to_row(event) do
    [
      event.user_id,
      event.plan_tier,
      event.method,
      event.path,
      event.status_code,
      event.duration_ms,
      if(event.error, do: 1, else: 0),
      DateTime.utc_now()
    ]
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end

  defp cancel_timer(ref) do
    Process.cancel_timer(ref)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: 30_000,
      type: :worker
    }
  end
end
