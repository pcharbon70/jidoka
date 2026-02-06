import Config

# Configuration for JidoCoderLib application
config :jido_coder_lib,
  # The base timeout for operations in milliseconds
  operation_timeout: 30_000,

  # Maximum number of concurrent operations
  max_concurrent_operations: 10,

  # Enable or disable telemetry
  enable_telemetry: true,

  # Log level
  log_level: :info

# LLM Provider Configuration
config :jido_coder_lib, :llm,
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
config :jido_coder_lib, :knowledge_engine,
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
config :jido_coder_lib, :knowledge_graph,
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
config :jido_coder_lib, :session,
  # Maximum number of concurrent sessions
  max_sessions: 100,
  # Session idle timeout in milliseconds (5 minutes)
  idle_timeout: 300_000,
  # Session absolute timeout in milliseconds (1 hour)
  absolute_timeout: 3_600_000,
  # Session cleanup interval in milliseconds (1 minute)
  cleanup_interval: 60_000

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
