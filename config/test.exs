import Config

# Configuration for test environment
config :jidoka,
  # Set environment to :test for proper test data paths
  env: :test,
  # In tests, we want shorter timeouts to fail fast
  operation_timeout: 5_000,

  # Disable non-essential features for faster tests
  enable_telemetry: false,

  # Use minimal logging in tests
  log_level: :warn

# Logger - Test Configuration
# Minimal logging for tests
config :logger,
  level: :warn,
  format: "$level $message\n",
  metadata: []

# LLM Provider - Test Configuration
config :jidoka, :llm,
  # Always use mock in tests
  provider: :mock,
  # Use a test model name
  model: "test-model",
  # Minimal timeout for tests
  request_timeout: 1_000

# Knowledge Graph - Test Configuration
config :jidoka, :knowledge_graph,
  # Use in-memory backend for tests
  backend: :native,
  # Small cache for tests
  cache_enabled: true,
  max_cache_size: 100

# Knowledge Engine - Test Configuration
config :jidoka, :knowledge_engine,
  # Use quad schema for multiple named graphs with ACL support
  schema: :quad,
  # Shorter health check interval for tests
  health_check_interval: 5_000,
  # Create standard graphs in tests
  create_standard_graphs: true

# Session Management - Test Configuration
config :jidoka, :session,
  # Fewer sessions for tests
  max_sessions: 5,
  # Short timeouts for tests
  idle_timeout: 5_000,
  absolute_timeout: 30_000,
  # Frequent cleanup in tests
  cleanup_interval: 1_000
