defmodule Jidoka.Protocol.MCP.Transport.Stdio do
  @moduledoc """
  STDIO transport for MCP client connections.

  This transport communicates with MCP servers that use standard input/output
  for JSON-RPC message exchange. Each message is a JSON object terminated by
  a newline character.

  ## Configuration Options

  * `:command` - The command to spawn (required)
  * `:cd` - Directory to run the command in (optional)
  * `:env` - Environment variables to set (optional)

  ## Example

      {:ok, pid} = Stdio.connect(command: "mcp-server")
      :ok = Stdio.send_message(pid, %{jsonrpc: "2.0", id: 1, method: "initialize", params: %{...}})
      :ok = Stdio.close(pid)
  """

  use GenServer
  require Logger
  @behaviour Jidoka.Protocol.MCP.Transport

  defstruct [:port, :owner, :buffer, :command]

  @type t :: %__MODULE__{
          port: port() | nil,
          owner: pid() | nil,
          buffer: binary(),
          command: binary() | nil
        }

  ## Client API

  @doc """
  Connect to an MCP server using STDIO transport.

  Spawns an external process and establishes communication via stdin/stdout.

  ## Options

  * `:command` - The command to execute (required)
  * `:cd` - Working directory for the command (optional)
  * `:env` - Environment variables as list of `{"KEY", "value"}` (optional)

  ## Examples

      {:ok, pid} = Stdio.connect(command: "uvx --from mcp test-server")
      {:ok, pid} = Stdio.connect(command: "node server.js", cd: "/path/to/server")

  """
  @impl true
  def connect(opts) when is_list(opts) do
    command = Keyword.fetch!(opts, :command)
    cd = Keyword.get(opts, :cd)
    env = Keyword.get(opts, :env, [])

    # Build port options
    port_opts = [:binary, :exit_status]
    port_opts = if cd, do: [:cd, cd | port_opts], else: port_opts
    port_opts = if env != [], do: [:env, env | port_opts], else: port_opts

    GenServer.start_link(__MODULE__, {command, port_opts, self()})
  end

  @doc """
  Send a message to the MCP server via stdin.

  The message will be JSON-encoded and sent with a newline terminator.

  ## Examples

      :ok = Stdio.send_message(pid, %{jsonrpc: "2.0", id: 1, method: "ping"})
      {:error, reason} = Stdio.send_message(pid, invalid_message)

  """
  @impl true
  def send_message(transport_pid, message) when is_pid(transport_pid) and is_map(message) do
    GenServer.call(transport_pid, {:send_message, message})
  catch
    :exit, reason -> {:error, {:exit, reason}}
    :error, reason -> {:error, reason}
  end

  @doc """
  Close the STDIO connection.

  Terminates the external process and cleans up resources.

  ## Examples

      :ok = Stdio.close(pid)

  """
  @impl true
  def close(transport_pid) when is_pid(transport_pid) do
    GenServer.call(transport_pid, :close)
  catch
    :exit, _ -> :ok
  end

  ## Server Callbacks

  @impl true
  def init({command, port_opts, owner}) do
    # Spawn the external process
    port = Port.open({:spawn, command}, port_opts)

    # Monitor the port
    Port.monitor(port)

    state = %__MODULE__{
      port: port,
      owner: owner,
      buffer: <<>>,
      command: command
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    case Jason.encode(message) do
      {:ok, json} ->
        # Send JSON with newline terminator
        send(state.port, {self(), {:command, :send, json <> "\n"}})
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, {:encode_error, reason}}, state}
    end
  end

  def handle_call(:close, _from, state) do
    # Close the port, which will terminate the process
    Port.close(state.port)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({port, {:data, {:line, line}}}, state) when port == state.port do
    # Received a complete line (JSON message)
    case Jason.decode(line) do
      {:ok, message} ->
        # Forward the decoded message to the owner
        send(state.owner, {:mcp_message, message})
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Failed to decode JSON: #{inspect(reason)}, line: #{line}")
        send(state.owner, {:mcp_error, {:decode_error, reason, line}})
        {:noreply, state}
    end
  end

  def handle_info({port, {:data, {:noeol, data}}}, state) when port == state.port do
    # Partial line received (shouldn't happen with :line mode, but handle it)
    Logger.warning("Received partial data without newline: #{inspect(data)}")
    {:noreply, %{state | buffer: state.buffer <> data}}
  end

  def handle_info({port, {:exit_status, status}}, state) when port == state.port do
    # Process exited
    Logger.info("MCP STDIO process exited with status: #{status}")
    send(state.owner, {:mcp_disconnected, {:exit_status, status}})
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, state) when port == state.port do
    # Port was closed or crashed
    Logger.warning("MCP STDIO port went down: #{inspect(reason)}")
    send(state.owner, {:mcp_disconnected, {:port_down, reason}})
    {:stop, {:port_down, reason}, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message in Stdio transport: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Ensure port is closed
    if state.port do
      Port.close(state.port)
    end

    :ok
  end
end
