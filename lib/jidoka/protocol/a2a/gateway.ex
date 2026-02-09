defmodule Jidoka.Protocol.A2A.Gateway do
  @moduledoc """
  Agent-to-Agent (A2A) Gateway for cross-framework agent communication.

  This module implements a JSON-RPC 2.0 based gateway for communicating
  with agents from other frameworks (AutoGen, LangChain, etc.).

  ## Features

  - Agent discovery via directory or static configuration
  - JSON-RPC 2.0 request/response handling
  - Message routing to local agents via Registry
  - Agent Card publication and caching
  - HTTP-based transport

  ## Configuration

  The gateway is configured via `config :jidoka, :a2a_gateway`:

  - `:agent_card` - This agent's card configuration
  - `:directory_url` - Optional agent directory URL
  - `:known_agents` - Static map of known agents
  - `:allowed_agents` - Local agents that can receive external messages
  - `:timeout` - Request timeout in milliseconds

  ## Example

      # Start the gateway
      {:ok, pid} = Gateway.start_link(name: :a2a_gateway)

      # Discover an agent
      {:ok, card} = Gateway.discover_agent(:a2a_gateway, "agent:external:assistant")

      # Send a message
      {:ok, response} = Gateway.send_message(
        :a2a_gateway,
        "agent:external:assistant",
        %{type: "text", content: "Hello!"}
      )

  """

  use GenServer
  require Logger

  alias Jidoka.Protocol.A2A.{AgentCard, JSONRPC, Registry}
  alias Jidoka.Signals

  @type status :: :initializing | :ready | :closing | :terminated
  @type agent_id :: String.t()
  @type state :: %__MODULE__{
          status: status(),
          agent_card: AgentCard.t() | nil,
          known_agents: map(),
          discovered_agents: map(),
          pending_requests: map(),
          request_id_counter: integer(),
          config: map()
        }

  defstruct [
    :status,
    :agent_card,
    known_agents: %{},
    discovered_agents: %{},
    pending_requests: %{},
    request_id_counter: 0,
    config: %{}
  ]

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts the A2A Gateway.

  ## Options

  * `:name` - Optional name for registration (default: `__MODULE__`)
  * `:agent_card` - Override agent card configuration
  * `:directory_url` - Override agent directory URL
  * `:known_agents` - Override static agent configuration
  * `:allowed_agents` - Local agents that can receive external messages

  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current status of the gateway.

  """
  def status(gateway \\ __MODULE__) do
    GenServer.call(gateway, :status)
  end

  @doc """
  Gets this gateway's Agent Card.

  """
  def get_agent_card(gateway \\ __MODULE__) do
    GenServer.call(gateway, :get_agent_card)
  end

  @doc """
  Discovers an agent by ID from the directory or static configuration.

  ## Parameters

  - `gateway` - The gateway process
  - `agent_id` - The agent ID to discover

  ## Returns

  - `{:ok, agent_card}` - Agent found
  - `{:error, :not_found}` - Agent not found
  - `{:error, reason}` - Discovery failed

  """
  def discover_agent(gateway \\ __MODULE__, agent_id) when is_binary(agent_id) do
    GenServer.call(gateway, {:discover_agent, agent_id})
  end

  @doc """
  Lists all known agents (static and discovered).

  """
  def list_agents(gateway \\ __MODULE__) do
    GenServer.call(gateway, :list_agents)
  end

  @doc """
  Sends a message to a remote agent via JSON-RPC.

  ## Parameters

  - `gateway` - The gateway process
  - `to_agent_id` - The target agent ID
  - `message` - The message map to send
  - `opts` - Optional keyword list

  ## Options

  - `:timeout` - Override default request timeout
  - `:method` - RPC method to call (default: "agent.send_message")

  ## Returns

  - `{:ok, response}` - Message delivered successfully
  - `{:error, reason}` - Failed to send

  ## Examples

      {:ok, response} = Gateway.send_message(
        :a2a_gateway,
        "agent:external:assistant",
        %{type: "text", content: "Hello!"}
      )

  """
  def send_message(gateway \\ __MODULE__, to_agent_id, message, opts \\ [])
      when is_binary(to_agent_id) and is_map(message) do
    timeout = Keyword.get(opts, :timeout)
    method = Keyword.get(opts, :method, "agent.send_message")
    GenServer.call(gateway, {:send_message, to_agent_id, method, message, timeout}, timeout || :infinity)
  end

  @doc """
  Handles an incoming A2A message from another agent.

  This should be called by the transport layer when a request is received.

  ## Parameters

  - `gateway` - The gateway process
  - `request` - The JSON-RPC request map

  ## Returns

  - `{:ok, response_map}` - Response to send back

  """
  def handle_incoming(gateway \\ __MODULE__, request) when is_map(request) do
    GenServer.call(gateway, {:handle_incoming, request})
  end

  @doc """
  Registers a local agent to receive external A2A messages.

  ## Parameters

  - `agent_id` - The local agent's identifier (e.g., `:coordinator`)
  - `pid` - The process to handle messages (default: `self()`)

  ## Returns

  - `:ok` - Successfully registered
  - `{:error, reason}` - Failed to register

  """
  def register_local_agent(agent_id, pid \\ self()) do
    Registry.register(agent_id, pid)
  end

  @doc """
  Unregisters a local agent from receiving external A2A messages.

  """
  def unregister_local_agent(agent_id) do
    Registry.unregister(agent_id)
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    # Load configuration
    config = Application.get_env(:jidoka, :a2a_gateway, [])
    agent_card_config = Keyword.get(opts, :agent_card, config[:agent_card] || %{})
    known_agents = Keyword.get(opts, :known_agents, config[:known_agents] || %{})
    directory_url = Keyword.get(opts, :directory_url, config[:directory_url])

    # Build our Agent Card
    agent_card =
      case AgentCard.for_jidoka(agent_card_config) do
        %AgentCard{} = card -> card
        {:ok, %AgentCard{} = card} -> card
        card when is_struct(card) -> card
      end

    state = %__MODULE__{
      status: :initializing,
      agent_card: agent_card,
      known_agents: normalize_known_agents(known_agents),
      discovered_agents: %{},
      pending_requests: %{},
      request_id_counter: 0,
      config: %{
        directory_url: directory_url,
        allowed_agents: Keyword.get(opts, :allowed_agents, config[:allowed_agents] || [])
      }
    }

    Logger.info("A2A Gateway initializing: #{agent_card.id}")

    # Start the registry
    case Jidoka.Protocol.A2A.Registry.start_link() do
      {:ok, _pid} ->
        ready_state = set_ready(state)
        # Dispatch connection state signal
        _ = Signals.a2a_connection_state(__MODULE__, :ready, gateway_name: __MODULE__, dispatch: true)
        {:ok, ready_state}

      {:error, {:already_started, _pid}} ->
        # Registry already started, continue
        ready_state = set_ready(state)
        # Dispatch connection state signal
        _ = Signals.a2a_connection_state(__MODULE__, :ready, gateway_name: __MODULE__, dispatch: true)
        {:ok, ready_state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_call(:get_agent_card, _from, state) do
    {:reply, {:ok, state.agent_card}, state}
  end

  @impl true
  def handle_call({:discover_agent, agent_id}, _from, state) do
    # First check known agents
    case Map.get(state.known_agents, agent_id) do
      nil ->
        # Check discovered agents cache
        case Map.get(state.discovered_agents, agent_id) do
          nil ->
            # Try directory lookup
            case discover_from_directory(agent_id, state) do
              {:ok, agent_card} ->
                # Cache the discovered agent
                new_discovered = Map.put(state.discovered_agents, agent_id, agent_card)
                # Dispatch agent discovered signal
                _ = Signals.a2a_agent_discovered(
                  agent_id,
                  agent_card,
                  :directory,
                  gateway_name: __MODULE__,
                  dispatch: true
                )
                {:reply, {:ok, agent_card}, %{state | discovered_agents: new_discovered}}

              {:error, _reason} = error ->
                {:reply, error, state}
            end

          agent_card ->
            # Dispatch agent discovered signal (cache hit)
            _ = Signals.a2a_agent_discovered(
              agent_id,
              agent_card,
              :cache,
              gateway_name: __MODULE__,
              dispatch: true
            )
            {:reply, {:ok, agent_card}, state}
        end

      agent_config ->
        # Found in known agents - fetch or return card
        case agent_config do
          %{agent_card: %{} = card} ->
            # Dispatch agent discovered signal (static)
            _ = Signals.a2a_agent_discovered(
              agent_id,
              card,
              :static,
              gateway_name: __MODULE__,
              dispatch: true
            )
            {:reply, {:ok, card}, state}

          _endpoint_config ->
            # Create a minimal card from the endpoint config
            card = %{
              id: agent_id,
              name: agent_id,
              type: ["External"],
              version: "unknown",
              capabilities: %{},
              endpoints: agent_config
            }
            # Dispatch agent discovered signal (static)
            _ = Signals.a2a_agent_discovered(
              agent_id,
              card,
              :static,
              gateway_name: __MODULE__,
              dispatch: true
            )
            {:reply, {:ok, card}, state}
        end
    end
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    all_agents =
      Map.keys(state.known_agents)
      |> Enum.concat(Map.keys(state.discovered_agents))
      |> Enum.uniq()

    {:reply, all_agents, state}
  end

  @impl true
  def handle_call({:send_message, to_agent_id, method, message, _timeout}, _from, state) do
    # First, ensure we have the agent's card/endpoints
    case get_agent_endpoint(to_agent_id, state) do
      {:ok, endpoint, auth} ->
        # Build JSON-RPC request
        request_id = next_request_id(state)

        params = %{
          from: state.agent_card.id,
          to: to_agent_id,
          message: message
        }

        json_rpc_request = JSONRPC.request(method, params, request_id)

        # Dispatch outgoing message signal (pending)
        _ = Signals.a2a_message(
          :outgoing,
          state.agent_card.id,
          to_agent_id,
          method,
          message,
          :pending,
          gateway_name: __MODULE__,
          dispatch: true
        )

        # Send via HTTP
        case send_http_request(endpoint, json_rpc_request, auth, state) do
          {:ok, response} ->
            # Parse the JSON-RPC response
            case JSONRPC.parse_response(response) do
              {:ok, :success, result} ->
                # Dispatch outgoing message signal (success)
                _ = Signals.a2a_message(
                  :outgoing,
                  state.agent_card.id,
                  to_agent_id,
                  method,
                  message,
                  :success,
                  gateway_name: __MODULE__,
                  response: result,
                  dispatch: true
                )
                {:reply, {:ok, result}, %{state | request_id_counter: request_id}}

              {:ok, :error, error} ->
                # Dispatch outgoing message signal (error)
                _ = Signals.a2a_message(
                  :outgoing,
                  state.agent_card.id,
                  to_agent_id,
                  method,
                  message,
                  :error,
                  gateway_name: __MODULE__,
                  response: error,
                  dispatch: true
                )
                {:reply, {:error, error}, %{state | request_id_counter: request_id}}

              {:error, :invalid_response} ->
                # Dispatch outgoing message signal (error)
                _ = Signals.a2a_message(
                  :outgoing,
                  state.agent_card.id,
                  to_agent_id,
                  method,
                  message,
                  :error,
                  gateway_name: __MODULE__,
                  response: :invalid_response,
                  dispatch: true
                )
                {:reply, {:error, :invalid_response}, %{state | request_id_counter: request_id}}
            end

          {:error, reason} = error ->
            # Dispatch outgoing message signal (error)
            _ = Signals.a2a_message(
              :outgoing,
              state.agent_card.id,
              to_agent_id,
              method,
              message,
              :error,
              gateway_name: __MODULE__,
              response: reason,
              dispatch: true
            )
            {:reply, error, %{state | request_id_counter: request_id}}
        end

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:handle_incoming, request}, _from, state) do
    # Validate and parse the request
    case JSONRPC.parse_request(request) do
      {:ok, :request, method, params, _id} ->
        # Extract from_agent and message from params
        from_agent = Map.get(params, "from", Map.get(params, :from, "unknown"))
        message = Map.get(params, "message", %{})

        # Dispatch incoming message signal
        _ = Signals.a2a_message(
          :incoming,
          from_agent,
          state.agent_card.id,
          method,
          message,
          :pending,
          gateway_name: __MODULE__,
          dispatch: true
        )

        # Handle the request (pass request_id for proper response)
        response = handle_request(method, params, _id, state)

        # Dispatch incoming message signal (success)
        _ = Signals.a2a_message(
          :incoming,
          from_agent,
          state.agent_card.id,
          method,
          message,
          :success,
          gateway_name: __MODULE__,
          dispatch: true
        )

        {:reply, {:ok, response}, state}

      {:ok, :notification, method, params} ->
        # Extract from_agent and message from params
        from_agent = Map.get(params, "from", Map.get(params, :from, "unknown"))
        message = Map.get(params, "message", %{})

        # Dispatch incoming message signal
        _ = Signals.a2a_message(
          :incoming,
          from_agent,
          state.agent_card.id,
          method,
          message,
          :success,
          gateway_name: __MODULE__,
          dispatch: true
        )

        # Handle notification (no response expected)
        _ = handle_notification(method, params, state)
        notif_response = JSONRPC.success_response(nil, %{"status" => "received"})
        {:reply, {:ok, notif_response}, state}

      {:error, :invalid_request} ->
        error_response = JSONRPC.error_response(
          nil,
          JSONRPC.invalid_request(),
          "Invalid request"
        )
        {:reply, {:ok, error_response}, state}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp set_ready(state) do
    %{state | status: :ready}
  end

  defp normalize_known_agents(agents) when is_map(agents) do
    Map.new(agents, fn
      {id, %AgentCard{} = card} -> {id, %{agent_card: card}}
      {id, %{agent_card: _card} = config} when is_map(config) -> {id, config}
      {id, %{endpoint: _} = config} -> {id, config}
      {id, config} when is_list(config) -> {id, Enum.into(config, %{})}
      {id, endpoint} when is_binary(endpoint) -> {id, %{endpoint: endpoint}}
    end)
  end

  defp next_request_id(state) do
    state.request_id_counter + 1
  end

  defp discover_from_directory(agent_id, state) do
    case state.config.directory_url do
      nil ->
        {:error, :not_found}

      url ->
        # Try to fetch from directory
        directory_url = "#{url}/#{URI.encode(agent_id)}"

        case http_get(directory_url, %{}, state) do
          {:ok, body} ->
            case Jason.decode(body) do
              {:ok, agent_data} ->
                case AgentCard.from_json_ld(agent_data) do
                  {:ok, card} -> {:ok, card}
                  error -> error
                end

              {:error, _} ->
                {:error, :invalid_response}
            end

          {:error, _} ->
            {:error, :not_found}
        end
    end
  end

  defp get_agent_endpoint(agent_id, state) do
    case Map.get(state.known_agents, agent_id) do
      %{endpoint: endpoint} = config ->
        auth = Map.get(config, :authentication)
        {:ok, endpoint, auth}

      config when is_map(config) ->
        endpoint = Map.get(config, :endpoint)
        auth = Map.get(config, :authentication)
        {:ok, endpoint, auth}

      nil ->
        case Map.get(state.discovered_agents, agent_id) do
          %{endpoints: %{rpc: endpoint}} = card ->
            auth = Map.get(card, :authentication)
            {:ok, endpoint, auth}

          _ ->
            {:error, :not_found}
        end
    end
  end

  defp send_http_request(endpoint, request, auth, state) do
    url = endpoint

    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    headers =
      if auth do
        case auth do
          %{type: "bearer", token: token} ->
            [{"authorization", "Bearer #{token}"} | headers]

          %{token: token} ->
            [{"authorization", "Bearer #{token}"} | headers]

          _ ->
            headers
        end
      else
        headers
      end

    case Jason.encode(request) do
      {:ok, body} ->
        http_post(url, body, headers, state)

      {:error, _} = error ->
        error
    end
  end

  defp http_get(url, headers, _state) do
    # Using :hackney for HTTP requests (comes with :hackney dependency)
    case :hackney.request(:get, url, headers, "", []) do
      {:ok, _status, _headers, body} when is_binary(body) ->
        {:ok, body}

      {:ok, _status, _headers, body} when is_list(body) ->
        {:ok, IO.iodata_to_binary(body)}

      {:ok, status, _headers, _body} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp http_post(url, body, headers, _state) do
    case :hackney.request(:post, url, headers, body, []) do
      {:ok, 200, _headers, response_body} when is_binary(response_body) ->
        case Jason.decode(response_body) do
          {:ok, data} -> {:ok, data}
          error -> error
        end

      {:ok, 200, _headers, response_body} when is_list(response_body) ->
        body = IO.iodata_to_binary(response_body)
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          error -> error
        end

      {:ok, status, _headers, _body} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp handle_request("agent.send_message", params, request_id, state) do
    # Extract message fields
    from = Map.get(params, "from")
    to = Map.get(params, "to")
    message = Map.get(params, "message")

    Logger.debug("A2A Gateway: Received message from #{from} to #{to}")

    # Route to local agent if allowed
    case route_to_local_agent(to, message, from, state) do
      {:ok, result} ->
        JSONRPC.success_response(request_id, %{
          "status" => "delivered",
          "from" => state.agent_card.id,
          "result" => result
        })

      {:error, :agent_not_running} ->
        JSONRPC.error_response(
          request_id,
          JSONRPC.method_not_found(),
          "Agent not found or not accepting messages"
        )

      {:error, :not_allowed} ->
        JSONRPC.error_response(
          request_id,
          JSONRPC.method_not_found(),
          "Agent not allowed to receive external messages"
        )

      {:error, _reason} ->
        JSONRPC.error_response(
          request_id,
          JSONRPC.internal_error(),
          "Failed to deliver message"
        )
    end
  end

  defp handle_request(method, _params, _request_id, _state) do
    JSONRPC.error_response(
      nil,
      JSONRPC.method_not_found(),
      "Unknown method: #{method}"
    )
  end

  defp handle_notification("agent.ping", params, _state) do
    from = Map.get(params, "from")
    Logger.debug("A2A Gateway: Received ping from #{from}")
    :ok
  end

  defp handle_notification(_method, _params, _state) do
    :ok
  end

  defp route_to_local_agent(to_agent_id, message, from_agent_id, state) do
    # Check if the target agent is allowed to receive external messages
    allowed = state.config[:allowed_agents] || []

    # Convert agent_id to atom for registry lookup
    agent_name =
      if String.starts_with?(to_agent_id, "agent:jidoka:") do
        # Extract the agent name: "agent:jidoka:coordinator" => :coordinator
        to_agent_id
        |> String.replace("agent:jidoka:", "")
        |> String.to_atom()
      else
        nil
      end

    # If allowed list is empty, allow all agents (for testing)
    allowed_empty = Enum.empty?(allowed)

    if agent_name && (allowed_empty or agent_name in allowed) do
      case Registry.lookup(agent_name) do
        {:ok, pid} ->
          # Send the message to the agent
          send(pid, {:a2a_message, from_agent_id, message})
          {:ok, %{delivered_to: agent_name}}

        {:error, :not_found} ->
          {:error, :agent_not_running}
      end
    else
      {:error, :not_allowed}
    end
  end
end
