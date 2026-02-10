defmodule Jidoka.Protocol.MCP.RequestManager do
  @moduledoc """
  Manages pending MCP requests and correlates responses.

  The MCP protocol uses JSON-RPC 2.0 which requires correlating responses
  with their corresponding requests using the `id` field. This module
  tracks pending requests, handles timeouts, and routes responses back
  to waiting processes.

  ## State

  * `pending_requests` - Map of request_id to {from, method, timestamp}
  * `request_counter` - Counter for generating unique request IDs
  * `timeout` - Default timeout for requests (ms)

  ## Example

      {:ok, manager} = RequestManager.start_link([])
      {:ok, request_id} = RequestManager.register_request(manager, from, :tools_list)
      # Later, when response arrives:
      RequestManager.handle_response(manager, request_id, response)
  """

  use GenServer
  require Logger

  @default_timeout 30_000

  defstruct [:pending_requests, :request_counter, :timeout]

  ## Client API

  @doc """
  Start the request manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Register a pending request and get a unique request ID.

  Returns the request ID that should be sent to the MCP server.

  Note: This function captures the calling process's GenServer from
  information automatically, so responses can be replied to correctly.
  """
  def register_request(manager \\ __MODULE__, method) do
    GenServer.call(manager, {:register, method})
  end

  @doc """
  Cancel a pending request.
  """
  def cancel_request(manager \\ __MODULE__, request_id) do
    GenServer.call(manager, {:cancel, request_id})
  end

  @doc """
  Handle an incoming response and route it to the waiting process.

  Returns `:ok` if the request was found and routed, `{:error, :not_found}` otherwise.
  """
  def handle_response(manager \\ __MODULE__, request_id, response) do
    GenServer.call(manager, {:handle_response, request_id, response})
  end

  @doc """
  Get the count of pending requests.
  """
  def pending_count(manager \\ __MODULE__) do
    GenServer.call(manager, :pending_count)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    state = %__MODULE__{
      pending_requests: %{},
      request_counter: 0,
      timeout: timeout
    }

    # Start timeout check timer
    schedule_timeout_check()

    {:ok, state}
  end

  @impl true
  def handle_call({:register, method}, from, state) do
    request_id = state.request_counter + 1

    request = %{
      from: from,
      method: method,
      timestamp: System.monotonic_time(:millisecond)
    }

    new_state = %{state |
      request_counter: request_id,
      pending_requests: Map.put(state.pending_requests, request_id, request)
    }

    {:reply, {:ok, request_id}, new_state}
  end

  def handle_call({:cancel, request_id}, _from, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {_request, pending} ->
        {:reply, :ok, %{state | pending_requests: pending}}
    end
  end

  def handle_call({:handle_response, request_id, response}, _from, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {%{from: from, method: _method}, pending} ->
        # Reply to the waiting process
        GenServer.reply(from, {:ok, response})
        {:reply, :ok, %{state | pending_requests: pending}}
    end
  end

  def handle_call(:pending_count, _from, state) do
    {:reply, map_size(state.pending_requests), state}
  end

  @impl true
  def handle_info(:timeout_check, state) do
    now = System.monotonic_time(:millisecond)

    # Find and remove timed out requests
    {timed_out, remaining} =
      Enum.split_with(state.pending_requests, fn {_id, request} ->
        now - request.timestamp > state.timeout
      end)

    # Reply to timed out requests with error
    Enum.each(timed_out, fn {request_id, %{from: from}} ->
      GenServer.reply(from, {:error, {:timeout, request_id}})
    end)

    if map_size(timed_out) > 0 do
      Logger.warning("Timed out #{map_size(timed_out)} MCP request(s)")
    end

    # Schedule next check
    schedule_timeout_check()

    {:noreply, %{state | pending_requests: Map.new(remaining)}}
  end

  ## Private Functions

  defp schedule_timeout_check do
    # Check every second for timed out requests
    Process.send_after(self(), :timeout_check, 1000)
  end
end
