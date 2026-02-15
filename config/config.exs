import Config

# Configuration for Jidoka application
config :jidoka,
  # The base timeout for operations in milliseconds
  operation_timeout: 30_000,

  # Maximum number of concurrent operations
  max_concurrent_operations: 10,

  # Enable or disable telemetry
  enable_telemetry: true,

  # Log level
  log_level: :info

# LLM Provider Configuration
config :jidoka, :llm,
  # LLM provider: :openai, :anthropic, :ollama, :mock, :none
  provider: System.get_env("LLM_PROVIDER") || :openai,
  # Model to use (provider-specific)
  model: System.get_env("LLM_MODEL") || "gpt-4",
  # API key for the provider
  api_key: System.get_env("OPENAI_API_KEY"),
  # Maximum tokens for LLM responses
  max_tokens: 4096,
  # Temperature for generation (0.0 - 2.0)
  temperature: 0.7,
  # Request timeout in milliseconds
  request_timeout: 60_000

# Knowledge Graph Configuration (Phase 5)
config :jidoka, :knowledge_engine,
  # Data directory for triple store (relative to application root or absolute)
  data_dir: "data/knowledge_graph",
  # Schema type: :quad (required for multiple named graphs with ACL support)
  schema: :quad,
  # Health check interval in milliseconds (30 seconds)
  health_check_interval: 30_000,
  # Enable automatic creation of standard named graphs
  create_standard_graphs: true,
  # Standard named graphs to create on startup
  standard_graphs: [
    :long_term_context,
    :elixir_codebase,
    :conversation_history,
    :system_knowledge
  ]

# Legacy Knowledge Graph Configuration (deprecated, kept for compatibility)
config :jidoka, :knowledge_graph,
  # Backend: :native (in-memory), :remote_sparql
  backend: System.get_env("KNOWLEDGE_BACKEND") || :native,
  # SPARQL endpoint for remote backend
  sparql_endpoint: System.get_env("SPARQL_ENDPOINT") || "http://localhost:8080/sparql",
  # Enable query result caching
  cache_enabled: true,
  # Maximum cache size (number of results)
  max_cache_size: 10_000,
  # Cache TTL in milliseconds
  cache_ttl: 300_000

# Session Management Configuration
config :jidoka, :session,
  # Maximum number of concurrent sessions
  max_sessions: 100,
  # Session idle timeout in milliseconds (5 minutes)
  idle_timeout: 300_000,
  # Session absolute timeout in milliseconds (1 hour)
  absolute_timeout: 3_600_000,
  # Session cleanup interval in milliseconds (1 minute)
  cleanup_interval: 60_000

# MCP (Model Context Protocol) Configuration (Phase 8.3)
# Configure MCP servers here, e.g.:
# config :jidoka, :mcp_servers,
#   filesystem: [
#     transport: {:stdio, command: "npx -y @modelcontextprotocol/server-filesystem /path/to/allowed"},
#     name: :mcp_filesystem
#   ]
config :jidoka, :mcp_servers, %{}

# Phoenix Channels Configuration (Phase 8.4)
# Configure Phoenix Channels connections here, e.g.:
# config :jidoka, :phoenix_connections,
#   backend_service: [
#     name: :phoenix_backend,
#     uri: "ws://localhost:4000/socket/websocket",
#     headers: [{"X-API-Key", "your-api-key"}],
#     params: %{token: "auth-token"},
#     auto_join_channels: [{"room:lobby", %{}}]
#   ]
config :jidoka, :phoenix_connections, %{}

# A2A (Agent-to-Agent) Gateway Configuration (Phase 8.5)
# Configure A2A Gateway for cross-framework agent communication
config :jidoka, :a2a_gateway,
  # Agent Card configuration
  agent_card: %{
    # Agent type classification
    type: ["Jidoka", "Coordinator"],
    # Additional capabilities to advertise
    capabilities: %{
      tools: [],
      accepts: ["text/plain", "application/json", "application/json-rpc+json"],
      produces: ["application/json", "application/json-rpc+json"]
    }
  },
  # Agent Directory for discovery (optional)
  directory_url: nil,
  # Known remote agents (static configuration)
  known_agents: %{},
  # Local agents allowed to receive external A2A messages
  allowed_agents: [:coordinator],
  # Request timeout in milliseconds
  timeout: 30_000,
  # HTTP client options
  http_options: [
    recv_timeout: 30_000,
    max_retries: 3
  ]

# Logger Configuration
config :logger,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ],
  metadata: [
    :request_id,
    :module,
    :function,
    :line,
    :pid,
    :application
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
