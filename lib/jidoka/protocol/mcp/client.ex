defmodule Jidoka.Protocol.MCP.Client do
  @moduledoc """
  MCP client GenServer for connecting to and communicating with MCP servers.

  This module implements the core MCP client functionality including:
  - Connection lifecycle (initialization, ready, shutdown)
  - Tool discovery and execution
  - Message correlation and timeout handling
  - Capability negotiation

  ## Configuration

  The client accepts the following options:

  * `:transport` - Transport type and configuration (required)
    * `{:stdio, [command: "mcp-server"]}` - STDIO transport
    * `{:http, [url: "http://localhost:3000/mcp"]}` - HTTP transport (future)
  * `:name` - Optional name for the client
  * `:timeout` - Request timeout in milliseconds (default: 30000)

  ## Example

      # Start a client with STDIO transport
      {:ok, pid} = Client.start_link(
        transport: {:stdio, command: "uvx --from mcp test-server"},
        name: :my_mcp_server
      )

      # List available tools
      {:ok, tools} = Client.list_tools(:my_mcp_server)

      # Call a tool
      {:ok, result} = Client.call_tool(:my_mcp_server, "echo", %{text: "Hello"})

      # Stop the client
      :ok = Client.stop(:my_mcp_server)
  """

  use GenServer
  require Logger

  alias Jidoka.Protocol.MCP.{Transport, RequestManager}

  defstruct [
    :transport_pid,
    :transport_type,
    :request_manager,
    :server_capabilities,
    :client_info,
    :status,
    :name,
    :pending_requests,
    :request_id_counter,
    :timeout
  ]

  @type status :: :initializing | :ready | :closing | :terminated
  @type transport_config :: {:stdio, Keyword.t()} | {:http, Keyword.t()}

  ## Client API

  @doc """
  Start an MCP client.

  ## Options

  * `:transport` - Required. Transport configuration tuple `{:stdio, [command: "cmd"]}` or `{:http, [url: "url"]}`
  * `:name` - Optional. Process name
  * `:timeout` - Optional. Request timeout (default: 30_000ms)

  ## Examples

      {:ok, pid} = Jidoka.Protocol.MCP.Client.start_link(
        transport: {:stdio, [command: "node server.js"]}
      )

      {:ok, pid} = Jidoka.Protocol.MCP.Client.start_link(
        transport: {:http, [url: "http://localhost:3000/mcp"]},
        name: :my_mcp_client
      )

  ## Returns

  * `{:ok, pid}` - Client started successfully
  * `{:error, {:transport_error, reason}}` - Transport configuration invalid or not implemented
  * `{:error, reason}` - Other error

  """
  def start_link(opts) do
    unless Keyword.has_key?(opts, :transport) do
      raise ArgumentError, "required option :transport not found"
    end

    {transport_config, opts} = Keyword.pop!(opts, :transport)
    name = Keyword.get(opts, :name)
    timeout = Keyword.get(opts, :timeout, 30_000)

    # Validate transport before starting the GenServer
    # This prevents starting child processes that will immediately fail
    case validate_transport(transport_config) do
      :ok ->
        GenServer.start_link(__MODULE__, {transport_config, name, timeout}, name: name)

      {:error, reason} ->
        {:error, {:transport_error, reason}}
    end
  end

  @doc """
  Stop the MCP client.
  """
  def stop(client \\ __MODULE__) do
    GenServer.stop(client, :normal, 5000)
  end

  @doc """
  Get the current status of the client.
  """
  def status(client \\ __MODULE__) do
    GenServer.call(client, :status)
  end

  @doc """
  Get the server's capabilities.
  """
  def capabilities(client \\ __MODULE__) do
    GenServer.call(client, :capabilities)
  end

  @doc """
  List available tools from the MCP server.

  Returns `{:ok, tools}` where tools is a list of tool maps with:
  * `:name` - Tool identifier
  * `:description` - Tool description
  * `:inputSchema` - JSON Schema for arguments
  """
  def list_tools(client \\ __MODULE__) do
    GenServer.call(client, {:tools_list})
  end

  @doc """
  Call a tool on the MCP server.

  ## Parameters

  * `client` - The client pid or name
  * `tool_name` - The name of the tool to call
  * `arguments` - Map of arguments matching the tool's input schema

  ## Returns

  * `{:ok, result}` - Tool executed successfully, result contains content array
  * `{:error, reason}` - Tool execution failed

  ## Example

      {:ok, result} = Client.call_tool(client, "calculate", %{a: 1, b: 2})
  """
  def call_tool(client \\ __MODULE__, tool_name, arguments) when is_binary(tool_name) and is_map(arguments) do
    GenServer.call(client, {:call_tool, tool_name, arguments})
  end

  @doc """
  List available resources from the MCP server.
  """
  def list_resources(client \\ __MODULE__, cursor \\ nil) do
    GenServer.call(client, {:resources_list, cursor})
  end

  @doc """
  Read a resource from the MCP server.
  """
  def read_resource(client \\ __MODULE__, uri) when is_binary(uri) do
    GenServer.call(client, {:resources_read, uri})
  end

  @doc """
  Send a ping to the MCP server.
  """
  def ping(client \\ __MODULE__) do
    GenServer.call(client, :ping)
  end

  ## Private Functions

  @doc """
  Validate transport configuration before starting the GenServer.
  """
  defp validate_transport({:stdio, opts}) when is_list(opts) do
    if Keyword.has_key?(opts, :command) do
      :ok
    else
      {:error, :missing_command_option}
    end
  end

  defp validate_transport({:http, _opts}) do
    {:error, :http_not_yet_implemented}
  end

  defp validate_transport({type, _opts}) do
    {:error, {:unknown_transport_type, type}}
  end

  ## Server Callbacks

  @impl true
  def init({transport_config, name, timeout}) do
    # Start request manager
    {:ok, request_manager} = RequestManager.start_link(timeout: timeout)

    state = %__MODULE__{
      transport_pid: nil,
      transport_type: elem(transport_config, 0),
      request_manager: request_manager,
      server_capabilities: nil,
      client_info: %{
        name: "jidoka",
        version: "0.1.0"
      },
      status: :initializing,
      name: name,
      pending_requests: %{},
      request_id_counter: 0,
      timeout: timeout
    }

    # Connect to transport
    case connect_transport(transport_config, state) do
      {:ok, transport_pid} ->
        new_state = %{state | transport_pid: transport_pid}
        # Send initialize request
        send_init_request(new_state)
        {:ok, new_state}

      {:error, reason} ->
        {:stop, {:transport_error, reason}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:capabilities, _from, state) do
    {:reply, state.server_capabilities, state}
  end

  def handle_call({:tools_list}, _from, %{status: :ready} = state) do
    request_id = next_request_id(state)

    request = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => "tools/list",
      "params" => %{}
    }

    case send_request(state, request_id, request, :tools_list) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:tools_list}, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call({:call_tool, tool_name, arguments}, _from, %{status: :ready} = state) do
    request_id = next_request_id(state)

    request = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => "tools/call",
      "params" => %{
        "name" => tool_name,
        "arguments" => arguments
      }
    }

    case send_request(state, request_id, request, {:call_tool, tool_name}) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:call_tool, _tool_name, _arguments}, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call({:resources_list, cursor}, _from, %{status: :ready} = state) do
    request_id = next_request_id(state)

    params = if cursor, do: %{cursor: cursor}, else: %{}

    request = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => "resources/list",
      "params" => params
    }

    case send_request(state, request_id, request, {:resources_list, cursor}) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:resources_read, uri}, _from, %{status: :ready} = state) do
    request_id = next_request_id(state)

    request = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => "resources/read",
      "params" => %{
        "uri" => uri
      }
    }

    case send_request(state, request_id, request, {:resources_read, uri}) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:ping, _from, %{status: :ready} = state) do
    request_id = next_request_id(state)

    request = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => "ping",
      "params" => %{}
    }

    case send_request(state, request_id, request, :ping) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:mcp_message, message}, state) do
    handle_incoming_message(message, state)
  end

  def handle_info({:mcp_error, error}, state) do
    Logger.error("MCP transport error: #{inspect(error)}")
    {:noreply, state}
  end

  def handle_info({:mcp_disconnected, reason}, state) do
    Logger.warning("MCP server disconnected: #{inspect(reason)}")
    {:stop, {:disconnected, reason}, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message in MCP.Client: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Close transport if still open
    if state.transport_pid do
      close_transport(state)
    end

    :ok
  end

  ## Private Functions

  defp connect_transport({:stdio, opts}, _state) do
    Transport.Stdio.connect(opts)
  end

  defp connect_transport({:http, _opts}, _state) do
    {:error, :http_not_yet_implemented}
  end

  defp close_transport(state) do
    case state.transport_type do
      :stdio -> Transport.Stdio.close(state.transport_pid)
      :http -> :ok # TODO: implement HTTP close
    end
  end

  defp send_init_request(state) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-03-26",
        "capabilities" => %{
          "roots" => %{"listChanged" => true},
          "sampling" => %{}
        },
        "clientInfo" => state.client_info
      }
    }

    # Register as a special init request (no reply expected directly)
    send_transport_message(state, request)
  end

  defp send_initialized_notification(state) do
    notification = %{
      "jsonrpc" => "2.0",
      "method" => "initialized"
    }

    send_transport_message(state, notification)
  end

  defp send_request(state, request_id, request, method) do
    # Register with request manager
    case RequestManager.register_request(state.request_manager, {self(), method}, method) do
      ^request_id ->
        case send_transport_message(state, request) do
          :ok ->
            new_state = %{state | request_id_counter: request_id}
            {:ok, new_state}

          {:error, reason} ->
            # Cancel the request
            RequestManager.cancel_request(state.request_manager, request_id)
            {:error, {:send_failed, reason}}
        end
    end
  end

  defp send_transport_message(state, message) do
    case state.transport_type do
      :stdio ->
        Transport.Stdio.send_message(state.transport_pid, message)

      :http ->
        {:error, :http_not_yet_implemented}
    end
  end

  defp handle_incoming_message(%{"id" => request_id} = message, state) do
    # This is a response to a request
    case RequestManager.handle_response(state.request_manager, request_id, message) do
      :ok ->
        {:noreply, state}

      {:error, :not_found} ->
        Logger.warning("Received response for unknown request ID: #{request_id}")
        {:noreply, state}
    end
  end

  defp handle_incoming_message(%{"result" => result, "method" => "initialize"}, state) do
    # Initialize response
    Logger.info("MCP server initialized: #{inspect(result["serverInfo"])}")

    # Store server capabilities
    capabilities = Map.get(result, "capabilities", %{})
    new_state = %{state | server_capabilities: capabilities, status: :ready}

    # Send initialized notification
    send_initialized_notification(new_state)

    {:noreply, new_state}
  end

  defp handle_incoming_message(%{"error" => error}, state) do
    # Error response
    Logger.error("MCP error response: #{inspect(error)}")
    {:noreply, state}
  end

  defp handle_incoming_message(%{"method" => method} = notification, state) when is_binary(method) do
    # Server-initiated notification
    handle_notification(notification, state)
  end

  defp handle_incoming_message(message, state) do
    Logger.warning("Unknown MCP message format: #{inspect(message)}")
    {:noreply, state}
  end

  defp handle_notification(%{"method" => "notifications/message", "params" => params}, state) do
    # Log message from server
    level = Map.get(params, "level", "info")
    message = Map.get(params, "data", "")

    case level do
      "debug" -> Logger.debug("MCP Server: #{message}")
      "info" -> Logger.info("MCP Server: #{message}")
      "warning" -> Logger.warning("MCP Server: #{message}")
      "error" -> Logger.error("MCP Server: #{message}")
      _ -> Logger.info("MCP Server [#{level}]: #{message}")
    end

    {:noreply, state}
  end

  defp handle_notification(notification, state) do
    Logger.debug("Unhandled MCP notification: #{inspect(notification)}")
    {:noreply, state}
  end

  defp next_request_id(state) do
    state.request_id_counter + 1
  end
end
