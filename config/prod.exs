import Config

# Configuration for production environment
config :jidoka,
  # Production defaults
  log_level: :info,

  # Standard timeouts
  operation_timeout: 30_000,

  # Enable telemetry in production
  enable_telemetry: true

# Logger - Production Configuration
# Structured logging for log aggregation systems
config :logger,
  level: :info,
  format: "$message\n",
  metadata: [:request_id, :module, :function, :pid, :application]

# LLM Provider - Production Configuration
# Note: API keys should be set via environment variables
config :jidoka, :llm,
  # Provider and model must be set via environment variables
  provider:
    System.get_env("LLM_PROVIDER") ||
      raise("""
      Environment variable LLM_PROVIDER is missing.
      Please set LLM_PROVIDER to one of: :openai, :anthropic, :ollama
      """),
  model:
    System.get_env("LLM_MODEL") ||
      raise("""
      Environment variable LLM_MODEL is missing.
      Please set LLM_MODEL to your desired model (e.g., "gpt-4", "claude-3-opus-20240229")
      """),
  # API key is required
  api_key:
    System.get_env("LLM_API_KEY") ||
      raise("""
      Environment variable LLM_API_KEY is missing.
      Please set LLM_API_KEY to your API key for the LLM provider.
      """),
  # Production timeouts
  request_timeout: 120_000

# Knowledge Graph - Production Configuration
config :jidoka, :knowledge_graph,
  # Production backend - use remote SPARQL for scalability
  backend: System.get_env("KNOWLEDGE_BACKEND", :remote_sparql),
  # SPARQL endpoint must be set
  sparql_endpoint:
    System.get_env("SPARQL_ENDPOINT") ||
      raise("""
      Environment variable SPARQL_ENDPOINT is missing.
      Please set SPARQL_ENDPOINT to your SPARQL endpoint URL.
      """),
  # Enable caching for performance
  cache_enabled: true,
  # Larger cache for production
  max_cache_size: 100_000,
  # Longer cache TTL
  cache_ttl: 600_000

# Session Management - Production Configuration
config :jidoka, :session,
  # Production session limits
  max_sessions: System.get_env("MAX_SESSIONS", "1000") |> String.to_integer(),
  # Standard timeouts
  # 5 minutes
  idle_timeout: 300_000,
  # 1 hour
  absolute_timeout: 3_600_000,
  # Less frequent cleanup in production
  # 5 minutes
  cleanup_interval: 300_000

# Phoenix Channels - Production Configuration
# Note: Configure Phoenix connections via environment variables
# Example:
#   PHOENIX_BACKEND_URL=wss://example.com/socket/websocket
#   PHOENIX_API_KEY=your-api-key
#   PHOENIX_AUTH_TOKEN=your-token
#
# config :jidoka, :phoenix_connections,
#   backend_service: [
#     name: :phoenix_backend,
#     uri: System.get_env("PHOENIX_BACKEND_URL") || "wss://example.com/socket/websocket",
#     headers: [{"X-API-Key", System.get_env("PHOENIX_API_KEY") || ""}],
#     params: %{token: System.get_env("PHOENIX_AUTH_TOKEN") || ""},
#     reconnect: true
#   ]
