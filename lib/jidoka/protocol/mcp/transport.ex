defmodule Jidoka.Protocol.MCP.Transport do
  @moduledoc """
  Behaviour for MCP transport implementations.

  Transports handle the communication layer between the MCP client
  and MCP servers, abstracting away the details of how messages
  are sent and received.

  ## Required Callbacks

  * `connect/2` - Establish a connection to an MCP server
  * `send_message/2` - Send a JSON-RPC message over the transport
  * `close/1` - Close the connection

  ## Built-in Transports

  * `Jidoka.Protocol.MCP.Transport.Stdio` - STDIO transport for local processes
  * `Jidoka.Protocol.MCP.Transport.HTTP` - HTTP transport for network connections

  ## Example

  To implement a custom transport:

      defmodule MyTransport do
        @behaviour Jidoka.Protocol.MCP.Transport

        def connect(opts) do
          # Return {:ok, transport_pid} or {:error, reason}
        end

        def send_message(transport_pid, message) when is_map(message) do
          # Send the message, return :ok or {:error, reason}
        end

        def close(transport_pid) do
          # Close the connection, return :ok
        end
      end
  """

  @type transport_pid :: pid()
  @type message :: map()
  @type opts :: Keyword.t()
  @type reason :: term()

  @doc """
  Establish a connection to an MCP server.

  Should return `{:ok, transport_pid}` on success or `{:error, reason}` on failure.
  """
  @callback connect(opts) :: {:ok, transport_pid} | {:error, reason} when opts: opts()

  @doc """
  Send a JSON-RPC message over the transport.

  The message is a map representing a JSON-RPC request, response, or notification.
  Should return `:ok` on success or `{:error, reason}` on failure.
  """
  @callback send_message(transport_pid, message) :: :ok | {:error, reason} when transport_pid: transport_pid(), message: message()

  @doc """
  Close the connection to the MCP server.

  Should return `:ok`.
  """
  @callback close(transport_pid) :: :ok when transport_pid: transport_pid()

  @optional_callbacks [close: 1]
end
