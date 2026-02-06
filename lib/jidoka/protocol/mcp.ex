defmodule Jidoka.Protocol.MCP do
  @moduledoc """
  Model Context Protocol (MCP) client implementation for Jidoka.

  This module provides a complete MCP client for integrating with external
  MCP servers that expose tools, resources, and prompts.

  ## What is MCP?

  MCP (Model Context Protocol) is an open protocol that enables AI applications
  to integrate with external tools and data sources. It uses JSON-RPC 2.0 for
  communication over transport layers like STDIO or HTTP.

  ## Features

  * STDIO transport for local MCP server processes
  * Tool discovery and execution
  * Resource reading and subscriptions
  * Connection pooling via dynamic supervisor
  * Capability negotiation
  * Error handling and timeout management

  ## Quick Start

  Add MCP servers to your config:

      config :jidoka, :mcp_servers,
        filesystem: [
          transport: {:stdio, command: "npx -y @modelcontextprotocol/server-filesystem /home/user/projects"},
          name: :mcp_filesystem
        ]

  Then use the client:

      # List available tools
      {:ok, tools} = Jidoka.Protocol.MCP.Client.list_tools(:mcp_filesystem)

      # Call a tool
      {:ok, result} = Jidoka.Protocol.MCP.Tools.call(:mcp_filesystem, "read_file", %{
        path: "/home/user/projects/README.md"
      })

  ## Modules

  * `Jidoka.Protocol.MCP.Client` - Main MCP client GenServer
  * `Jidoka.Protocol.MCP.ConnectionSupervisor` - Dynamic supervisor for connections
  * `Jidoka.Protocol.MCP.Tools` - Tool discovery and execution helpers
  * `Jidoka.Protocol.MCP.Capabilities` - Server capability queries
  * `Jidoka.Protocol.MCP.Transport` - Transport behaviour
  * `Jidoka.Protocol.MCP.Transport.Stdio` - STDIO transport implementation
  * `Jidoka.Protocol.MCP.RequestManager` - Request correlation and timeout handling
  * `Jidoka.Protocol.MCP.ErrorHandler` - Error translation and handling

  ## Server Configuration

  MCP servers can be configured in your `config/config.exs`:

      config :jidoka, :mcp_servers,
        # Filesystem access server
        filesystem: [
          transport: {:stdio, command: "npx -y @modelcontextprotocol/server-filesystem /allowed/path"},
          name: :mcp_filesystem
        ],

        # GitHub integration
        github: [
          transport: {:stdio, command: "uvx --from mcp-server-github mcp-server-github"},
          name: :mcp_github
        ],

        # Custom server
        custom: [
          transport: {:stdio, command: "./my-mcp-server"},
          name: :mcp_custom,
          timeout: 60_000  # 60 second timeout
        ]

  ## Transport Options

  ### STDIO Transport

      {:stdio, command: "command-to-run", cd: "/path", env: [{"KEY", "value"}]}

  ### HTTP Transport (not yet implemented)

      {:http, url: "http://localhost:3000/mcp"}

  """

  @doc """
  Start all configured MCP servers from application config.
  """
  def start_configured_servers do
    Jidoka.Protocol.MCP.ConnectionSupervisor.start_configured_servers()
  end

  @doc """
  List all active MCP connections.
  """
  def list_connections do
    Jidoka.Protocol.MCP.ConnectionSupervisor.list_connections()
  end

  @doc """
  Get tools from all active MCP servers.

  Returns a map of connection name to list of tools.
  """
  def list_all_tools do
    list_connections()
    |> Enum.map(fn {name, _pid} ->
      case Jidoka.Protocol.MCP.Tools.discover(name) do
        {:ok, tools} -> {name, tools}
        _ -> {name, []}
      end
    end)
    |> Map.new()
  end
end
