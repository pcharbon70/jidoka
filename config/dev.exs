import Config

# Configuration for development environment
config :jidoka,
  # In development, we want more verbose logging
  log_level: :debug,

  # Longer timeouts for development debugging
  operation_timeout: 60_000

# Disable telemetry metrics in development for faster startup
config :jidoka,
  enable_telemetry: false

# Logger - Development Configuration
# Verbose logging with colored output for development
config :logger,
  level: :debug,
  format: "[$level] $time $metadata$message\n",
  metadata: :all

# LLM Provider - Development Configuration
config :jidoka, :llm,
  # Use mock provider by default in development (no API key needed)
  provider: :mock,
  # Fallback to a small model for faster responses
  model: "gpt-4o-mini",
  # Lower timeouts for development
  request_timeout: 30_000

# Knowledge Graph - Development Configuration
config :jidoka, :knowledge_graph,
  # Use in-memory backend for development
  backend: :native,
  # Disable caching in development to see fresh results
  cache_enabled: false

# Session Management - Development Configuration
config :jidoka, :session,
  # Fewer sessions for development
  max_sessions: 10,
  # Longer timeouts for debugging
  # 30 minutes
  idle_timeout: 1_800_000,
  # 24 hours
  absolute_timeout: 86_400_000

# Phoenix Channels - Development Configuration
# Example local development Phoenix connection
# config :jidoka, :phoenix_connections,
#   local_dev: [
#     name: :phoenix_local,
#     uri: "ws://localhost:4000/socket/websocket",
#     headers: [],
#     params: %{},
#     auto_join_channels: [{"room:lobby", %{}}]
#   ]

# A2A Gateway - Development Configuration
# Example A2A Gateway configuration for development
# config :jidoka, :a2a_gateway,
#   directory_url: "http://localhost:4000/a2a/directory",
#   known_agents: %{
#     "agent:test:external" => %{
#       endpoint: "http://localhost:5000/a2a/rpc",
#       authentication: %{token: "dev-token"}
#     }
#   }
