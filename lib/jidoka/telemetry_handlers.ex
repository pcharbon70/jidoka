defmodule Jidoka.TelemetryHandlers do
  @moduledoc """
  Telemetry event handlers for Jidoka.

  This module provides handler functions that can be attached to telemetry events.
  Handlers can aggregate metrics, log significant events, or forward data to external systems.

  ## Attaching Handlers

  Handlers are attached in the application startup:

      Jidoka.TelemetryHandlers.attach_log_handler()
      Jidoka.TelemetryHandlers.attach_metrics_handler()

  ## Handler Types

  ### Log Handler
  Logs significant telemetry events at appropriate levels.

  ### Metrics Handler
  Aggregates telemetry events into counters and histograms.

  ## Detaching Handlers

  Handlers can be detached during shutdown:

      Jidoka.TelemetryHandlers.detach_log_handler()
      Jidoka.TelemetryHandlers.detach_metrics_handler()

  """

  require Logger

  @doc """
  Attaches the log handler for telemetry events.

  The log handler logs significant events at appropriate log levels:
  - Errors are logged at :error level
  - Long-running operations are logged at :warn level
  - Session lifecycle events are logged at :info level

  ## Returns

  `:ok` if the handler is attached successfully.
  `{:error, :already_exists}` if the handler is already attached.

  ## Example

      Jidoka.TelemetryHandlers.attach_log_handler()

  """
  @spec attach_log_handler() :: :ok | {:error, term()}
  def attach_log_handler do
    handler_id = "jidoka-telemetry-log-handler"

    :telemetry.attach(
      handler_id,
      # Attach to all jidoka events
      [:jidoka, :_, :_],
      &handle_log_event/4,
      nil
    )
  end

  @doc """
  Detaches the log handler.

  ## Returns

  `:ok` if the handler was detached, `{:error, :not_found}` if not attached.

  """
  @spec detach_log_handler() :: :ok | {:error, :not_found}
  def detach_log_handler do
    :telemetry.detach("jidoka-telemetry-log-handler")
  end

  @doc """
  Attaches the metrics handler for telemetry events.

  The metrics handler aggregates events into:
  - Event counters (count of each event type)
  - Duration histograms (timing data)

  ## Returns

  `:ok` if the handler is attached successfully.
  `{:error, :already_exists}` if the handler is already attached.

  ## Example

      Jidoka.TelemetryHandlers.attach_metrics_handler()

  """
  @spec attach_metrics_handler() :: :ok | {:error, term()}
  def attach_metrics_handler do
    handler_id = "jidoka-telemetry-metrics-handler"

    :telemetry.attach(
      handler_id,
      # Attach to all jidoka events
      [:jidoka, :_, :_],
      &handle_metrics_event/4,
      nil
    )
  end

  @doc """
  Detaches the metrics handler.

  ## Returns

  `:ok` if the handler was detached, `{:error, :not_found}` if not attached.

  """
  @spec detach_metrics_handler() :: :ok | {:error, :not_found}
  def detach_metrics_handler do
    :telemetry.detach("jidoka-telemetry-metrics-handler")
  end

  @doc """
  Attaches all standard telemetry handlers.

  This is a convenience function that attaches all handlers at once.
  If handlers are already attached, returns `:ok`.

  ## Returns

  `:ok` if all handlers are attached successfully.

  ## Example

      Jidoka.TelemetryHandlers.attach_all()

  """
  @spec attach_all() :: :ok
  def attach_all do
    with :ok <- attach_log_handler(),
         :ok <- attach_metrics_handler() do
      :ok
    else
      {:error, :already_exists} -> :ok
    end
  end

  @doc """
  Detaches all telemetry handlers.

  ## Returns

  `:ok`

  ## Example

      Jidoka.TelemetryHandlers.detach_all()

  """
  @spec detach_all() :: :ok
  def detach_all do
    detach_log_handler()
    detach_metrics_handler()
    :ok
  end

  # Private Handler Functions

  defp handle_log_event(event, measurements, metadata, _config) do
    # Only log if telemetry is enabled in config
    if Application.get_env(:jidoka, :enable_telemetry, false) do
      log_event(event, measurements, metadata)
    end

    :ok
  end

  defp handle_metrics_event(_event, measurements, metadata, _config) do
    # Only track metrics if telemetry is enabled
    if Application.get_env(:jidoka, :enable_telemetry, false) do
      # Update counters
      increment_event_counter()

      # Track duration if available
      case measurements do
        %{duration: duration} when is_number(duration) ->
          track_duration(duration)

        _ ->
          :ok
      end

      # Track component-specific metrics
      track_component_metrics(metadata)
    end

    :ok
  end

  # Logging Logic

  defp log_event([:jidoka, component, action], measurements, metadata) do
    level = determine_log_level(component, action, measurements, metadata)
    message = format_log_message(component, action, measurements, metadata)

    Logger.log(level, message)
  end

  defp determine_log_level(:session, action, _measurements, _metadata)
       when action in [:started, :stopped] do
    :info
  end

  defp determine_log_level(:session, :error, _measurements, _metadata) do
    :error
  end

  defp determine_log_level(:agent, :error, _measurements, _metadata) do
    :error
  end

  defp determine_log_level(:llm, :error, _measurements, _metadata) do
    :error
  end

  defp determine_log_level(:llm, :response, %{duration: duration}, _metadata)
       when duration > 30_000 do
    :warn
  end

  defp determine_log_level(:context, :cache_eviction, _measurements, _metadata) do
    :warn
  end

  defp determine_log_level(_component, _action, _measurements, _metadata) do
    :debug
  end

  defp format_log_message(component, action, measurements, metadata) do
    duration_str = format_duration(measurements)

    base = "[#{component}/#{action}]"

    metadata_str =
      metadata
      # Limit to first 3 metadata fields
      |> Enum.take(3)
      |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v, limit: 50)}" end)
      |> Enum.join(" ")

    case {duration_str, metadata_str} do
      {"", ""} -> base
      {duration, ""} -> "#{base} #{duration}"
      {"", metadata} -> "#{base} #{metadata}"
      {duration, metadata} -> "#{base} #{duration} #{metadata}"
    end
  end

  defp format_duration(%{duration: duration}) when is_number(duration) do
    "duration=#{duration}ms"
  end

  defp format_duration(_), do: ""

  # Metrics Tracking Logic
  # In production, these would update actual metrics systems (Prometheus, StatsD, etc.)
  # For now, we'll use :counters and :ets for in-memory tracking

  @counter_table :jido_telemetry_counters
  @duration_table :jido_telemetry_durations

  defp increment_event_counter do
    ensure_tables_exist()

    key = {:events, :total}
    update_counter(@counter_table, key, 1)
  end

  defp track_duration(duration) when is_number(duration) do
    ensure_tables_exist()

    # Simple histogram tracking: count in buckets
    bucket = duration_bucket(duration)
    key = {:duration, bucket}
    update_counter(@counter_table, key, 1)

    # Store raw duration for percentile calculation (truncated list)
    key = :durations
    :ets.insert(@duration_table, {key, duration})
  end

  defp track_component_metrics(%{agent_id: _agent_id}) do
    ensure_tables_exist()
    update_counter(@counter_table, {:component, :agent}, 1)
  end

  defp track_component_metrics(%{session_id: _session_id}) do
    ensure_tables_exist()
    update_counter(@counter_table, {:component, :session}, 1)
  end

  defp track_component_metrics(_) do
    :ok
  end

  defp ensure_tables_exist do
    # Try to create counter table, ignore if already exists (fixes race condition)
    try do
      :ets.new(@counter_table, [:named_table, :protected, :set])
    rescue
      ArgumentError ->
        # Table already exists, this is OK
        :ok
    end

    # Try to create duration table, ignore if already exists (fixes race condition)
    try do
      :ets.new(@duration_table, [:named_table, :protected, :bag, read_concurrency: true])
    rescue
      ArgumentError ->
        # Table already exists, this is OK
        :ok
    end
  end

  defp update_counter(table, key, delta) do
    try do
      :ets.update_counter(table, key, {2, delta})
    rescue
      ArgumentError ->
        :ets.insert(table, {key, delta})
    end
  end

  defp duration_bucket(duration) when duration < 10, do: "<10ms"
  defp duration_bucket(duration) when duration < 50, do: "10-50ms"
  defp duration_bucket(duration) when duration < 100, do: "50-100ms"
  defp duration_bucket(duration) when duration < 500, do: "100-500ms"
  defp duration_bucket(duration) when duration < 1000, do: "500ms-1s"
  defp duration_bucket(duration) when duration < 5000, do: "1-5s"
  defp duration_bucket(duration) when duration < 30_000, do: "5-30s"
  defp duration_bucket(_duration), do: ">30s"

  @doc """
  Gets the current telemetry counters.

  Returns a map of counter values.

  ## Example

      iex> Jidoka.TelemetryHandlers.get_counters()
      %{events: %{total: 1523}, duration: %{"<10ms" => 800, "10-50ms" => 400, ...}}

  """
  @spec get_counters() :: map()
  def get_counters do
    ensure_tables_exist()

    counters =
      @counter_table
      |> :ets.tab2list()
      |> Enum.group_by(
        fn {key, _val} -> elem(key, 0) end,
        fn {_key, val} -> val end
      )

    Enum.into(counters, %{})
  end

  @doc """
  Resets all telemetry counters.

  ## Example

      Jidoka.TelemetryHandlers.reset_counters()

  """
  @spec reset_counters() :: :ok
  def reset_counters do
    if :ets.whereis(@counter_table) != :undefined do
      :ets.delete_all_objects(@counter_table)
    end

    if :ets.whereis(@duration_table) != :undefined do
      :ets.delete_all_objects(@duration_table)
    end

    :ok
  end

  @doc """
  Gets duration statistics.

  Returns a map with min, max, avg, and percentiles.

  ## Example

      iex> Jidoka.TelemetryHandlers.get_duration_stats()
      %{min: 5, max: 1523, avg: 87, p50: 65, p95: 450, p99: 980}

  """
  @spec get_duration_stats() :: map()
  def get_duration_stats do
    ensure_tables_exist()

    durations =
      case :ets.lookup(@duration_table, :durations) do
        [{:durations, values}] when is_list(values) -> values
        _ -> []
      end

    if Enum.empty?(durations) do
      %{min: 0, max: 0, avg: 0, count: 0}
    else
      sorted = Enum.sort(durations)
      count = length(sorted)
      sum = Enum.sum(sorted)

      %{
        min: List.first(sorted),
        max: List.last(sorted),
        avg: div(sum, count),
        count: count,
        p50: percentile(sorted, 50),
        p95: percentile(sorted, 95),
        p99: percentile(sorted, 99)
      }
    end
  end

  defp percentile(sorted_list, percentile) when is_list(sorted_list) do
    index = max(0, trunc(length(sorted_list) * percentile / 100) - 1)
    Enum.at(sorted_list, index, 0)
  end
end
