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

  ## Security

  Commands are validated against a whitelist to prevent arbitrary command execution.
  Only commands from trusted sources should be added to the whitelist.

  """

  use GenServer
  require Logger
  @behaviour Jidoka.Protocol.MCP.Transport

  # Command whitelist: allowed MCP server executables
  # Each entry can be:
  # - A simple string (exact executable name match)
  # - A tuple of {base_command, [allowed_args_pattern]} for stricter validation
  @allowed_commands [
    # Node.js-based MCP servers
    "node",
    "npx",

    # Python-based MCP servers (via uv, pipx, python)
    "uv",
    "uvx",
    "pipx",
    "python",
    "python3",

    # Other common MCP server runtimes
    "deno",
    "bun",
    "ruby",
    "java",
    "docker",

    # For testing/development (remove in production)
    "echo",
    "cat"
  ]

  # Commands that are explicitly forbidden regardless of whitelist
  @forbidden_commands [
    "rm",
    "del",
    "mv",
    "cp",
    "chmod",
    "chown",
    "sudo",
    "su",
    "bash",
    "sh",
    "zsh",
    "fish",
    "cmd",
    "powershell",
    "pwsh",
    "curl",
    "wget",
    "nc",
    "netcat",
    "telnet"
  ]

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
    command = Keyword.get(opts, :command)
    unless command do
      raise ArgumentError, "required option :command not found"
    end

    # Validate command against whitelist
    with :ok <- validate_command(command),
         cd = Keyword.get(opts, :cd),
         env = Keyword.get(opts, :env, []) do
      # Build port options
      # Use line-oriented mode to receive complete JSON messages
      port_opts = [:binary, {:line, 1}, :exit_status]
      port_opts = if cd, do: [{:cd, cd} | port_opts], else: port_opts
      port_opts = if env != [], do: [{:env, env} | port_opts], else: port_opts

      GenServer.start_link(__MODULE__, {command, port_opts, self()})
    else
      {:error, :command_not_allowed} ->
        # Extract base command for the error
        base_command =
          command
          |> String.trim()
          |> String.split()
          |> List.first("")
          |> Path.basename()

        {:error, {:command_not_whitelisted, base_command}}

      {:error, :command_forbidden} ->
        # For explicitly forbidden commands, return the same format
        base_command =
          command
          |> String.trim()
          |> String.split()
          |> List.first("")
          |> Path.basename()

        {:error, {:command_not_whitelisted, base_command}}

      {:error, :command_contains_forbidden_patterns} ->
        # Extract base command for the error
        base_command =
          command
          |> String.trim()
          |> String.split()
          |> List.first("")
          |> Path.basename()

        {:error, {:command_not_whitelisted, base_command}}

      {:error, :shell_injection_detected} ->
        # Extract base command for the error
        base_command =
          command
          |> String.trim()
          |> String.split()
          |> List.first("")
          |> Path.basename()

        {:error, {:command_not_whitelisted, base_command}}

      {:error, _reason} = error ->
        error
    end
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

  @doc """
  Get the list of whitelisted commands.

  Returns the combined default whitelist and any custom configured whitelist.

  ## Example

      iex> Stdio.command_whitelist()
      ["node", "npx", "python", "python3", ...]
  """
  @spec command_whitelist() :: [String.t()]
  def command_whitelist do
    default = @allowed_commands

    case Application.get_env(:jidoka, :mcp_allowed_commands) do
      nil -> default
      custom when is_list(custom) -> default ++ custom
    end
  end

  @doc """
  Check if a command is whitelisted.

  Returns `true` if the base command (first word) is in the whitelist,
  `false` otherwise.

  ## Example

      iex> Stdio.command_whitelisted?("npx mcp-server")
      true

      iex> Stdio.command_whitelisted?("rm -rf /")
      false
  """
  @spec command_whitelisted?(String.t()) :: boolean()
  def command_whitelisted?(command) when is_binary(command) do
    command
    |> String.trim()
    |> String.split()
    |> List.first("")
    |> Path.basename()
    |> then(fn base_command ->
      # First check if explicitly forbidden
      base_command not in @forbidden_commands and
        (base_command in @allowed_commands or
          base_command in List.wrap(Application.get_env(:jidoka, :mcp_allowed_commands)))
    end)
  end

  ## Server Callbacks

  @impl true
  def init({command, port_opts, owner}) do
    # Convert command string to charlist for Port.open
    # Erlang ports expect charlists for spawn commands
    command_charlist = String.to_charlist(command)

    # Spawn the external process
    port = Port.open({:spawn, command_charlist}, port_opts)

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

  def handle_info({port, {:badsig, _signal}}, state) when port == state.port do
    # Port received an unhandled signal - this can happen when the external
    # process receives signals like SIGTERM, SIGPIPE, etc. We log it but
    # don't crash the transport process.
    Logger.debug("MCP STDIO port received bad signal - ignoring")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message in Stdio transport: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Ensure port is closed, ignore errors if already closed
    if state.port != nil and is_port(state.port) do
      try do
        Port.close(state.port)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @doc false
  @spec validate_command(String.t()) :: :ok | {:error, atom()}
  def validate_command(command) when is_binary(command) do
    command = String.trim(command)

    with :ok <- check_forbidden_commands(command),
         :ok <- check_command_allowed(command),
         :ok <- check_for_shell_injection(command) do
      :ok
    end
  end

  # Check if command contains any forbidden substrings
  defp check_forbidden_commands(command) do
    forbidden_patterns = [
      # Shell operators that could lead to command injection
      ";", "&&", "||", "|", "\n", "\r", "\t",
      # Potential shell escapes
      "$(", "`", "${",
      # Output redirection
      ">", ">>", "<",
      # Background execution
      "&",
      # Command substitution
      "$(",
      # Potential file operations
      "/etc/passwd", "/etc/shadow"
    ]

    has_forbidden =
      Enum.any?(forbidden_patterns, fn pattern ->
        String.contains?(command, pattern)
      end)

    if has_forbidden do
      Logger.error("MCP STDIO: Command contains forbidden patterns: #{command}")
      {:error, :command_contains_forbidden_patterns}
    else
      :ok
    end
  end

  # Check if the base command is in the allowed list
  defp check_command_allowed(command) do
    # Extract the base command (first word)
    base_command =
      command
      |> String.split()
      |> List.first("")
      |> Path.basename()

    cond do
      base_command in @forbidden_commands ->
        Logger.error("MCP STDIO: Command is explicitly forbidden: #{base_command}")
        {:error, :command_forbidden}

      base_command in @allowed_commands ->
        :ok

      true ->
        # Check if there's a custom whitelist configured
        case Application.get_env(:jidoka, :mcp_allowed_commands) do
          nil ->
            Logger.error("MCP STDIO: Command not in whitelist: #{base_command}")
            {:error, :command_not_allowed}

          custom_whitelist when is_list(custom_whitelist) ->
            if base_command in custom_whitelist do
              :ok
            else
              Logger.error("MCP STDIO: Command not in custom whitelist: #{base_command}")
              {:error, :command_not_allowed}
            end
        end
    end
  end

  # Check for shell injection attempts
  defp check_for_shell_injection(command) do
    # Look for common shell injection patterns
    injection_patterns = [
      ~r/[;&|`$\()]/,  # Shell metacharacters
      ~r/\.\.[\/\\]/, # Directory traversal
      ~r/~\//,         # Home directory expansion
      ~r/\$\{/,       # Variable expansion
      ~r/eval\s/,     # eval statements
      ~r/exec\s/,     # exec statements
      ~r/system\s/    # system calls
    ]

    has_injection =
      Enum.any?(injection_patterns, fn pattern ->
        Regex.match?(pattern, command)
      end)

    if has_injection do
      Logger.error("MCP STDIO: Possible shell injection detected: #{command}")
      {:error, :shell_injection_detected}
    else
      :ok
    end
  end
end
