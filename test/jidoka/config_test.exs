defmodule Jidoka.ConfigTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for the Jidoka.Config configuration validation module.
  """

  # Reset config before each test
  setup do
    # Store original config
    original_llm = Application.get_env(:jidoka, :llm)
    original_kg = Application.get_env(:jidoka, :knowledge_graph)
    original_session = Application.get_env(:jidoka, :session)

    on_exit(fn ->
      # Restore original config
      if original_llm, do: Application.put_env(:jidoka, :llm, original_llm)
      if original_kg, do: Application.put_env(:jidoka, :knowledge_graph, original_kg)
      if original_session, do: Application.put_env(:jidoka, :session, original_session)
    end)

    :ok
  end

  describe "validate_all/0" do
    test "returns :ok when all configuration is valid" do
      # Set valid configuration
      Application.put_env(:jidoka, :llm,
        provider: :mock,
        model: "test-model",
        api_key: nil
      )

      Application.put_env(:jidoka, :knowledge_graph, backend: :native)

      Application.put_env(:jidoka, :session,
        max_sessions: 10,
        idle_timeout: 1000,
        absolute_timeout: 2000,
        cleanup_interval: 500
      )

      assert Jidoka.Config.validate_all() == :ok
    end

    test "returns errors when LLM provider is invalid" do
      Application.put_env(:jidoka, :llm,
        provider: :invalid_provider,
        model: "test-model"
      )

      Application.put_env(:jidoka, :knowledge_graph, backend: :native)

      Application.put_env(:jidoka, :session,
        max_sessions: 10,
        idle_timeout: 1000,
        absolute_timeout: 2000,
        cleanup_interval: 500
      )

      assert {:error, errors} = Jidoka.Config.validate_all()
      assert Enum.any?(errors, &String.contains?(&1, "LLM provider"))
    end

    test "returns errors when LLM model is missing" do
      Application.put_env(:jidoka, :llm,
        provider: :mock,
        model: nil
      )

      Application.put_env(:jidoka, :knowledge_graph, backend: :native)

      Application.put_env(:jidoka, :session,
        max_sessions: 10,
        idle_timeout: 1000,
        absolute_timeout: 2000,
        cleanup_interval: 500
      )

      assert {:error, errors} = Jidoka.Config.validate_all()
      assert Enum.any?(errors, &String.contains?(&1, "LLM model"))
    end

    test "returns errors when API key is missing for OpenAI" do
      # Clear any existing API key from previous tests
      Jidoka.SecureCredentials.delete_api_key(:openai)

      Application.put_env(:jidoka, :llm,
        provider: :openai,
        model: "gpt-4",
        api_key: nil
      )

      Application.put_env(:jidoka, :knowledge_graph, backend: :native)

      Application.put_env(:jidoka, :session,
        max_sessions: 10,
        idle_timeout: 1000,
        absolute_timeout: 2000,
        cleanup_interval: 500
      )

      assert {:error, errors} = Jidoka.Config.validate_all()
      assert Enum.any?(errors, &String.contains?(&1, "API key"))
    end

    test "returns errors when knowledge graph backend is invalid" do
      Application.put_env(:jidoka, :llm,
        provider: :mock,
        model: "test-model"
      )

      Application.put_env(:jidoka, :knowledge_graph, backend: :invalid_backend)

      Application.put_env(:jidoka, :session,
        max_sessions: 10,
        idle_timeout: 1000,
        absolute_timeout: 2000,
        cleanup_interval: 500
      )

      assert {:error, errors} = Jidoka.Config.validate_all()
      assert Enum.any?(errors, &String.contains?(&1, "backend"))
    end

    test "returns errors when SPARQL endpoint is missing for remote backend" do
      Application.put_env(:jidoka, :llm,
        provider: :mock,
        model: "test-model"
      )

      Application.put_env(:jidoka, :knowledge_graph,
        backend: :remote_sparql,
        sparql_endpoint: nil
      )

      Application.put_env(:jidoka, :session,
        max_sessions: 10,
        idle_timeout: 1000,
        absolute_timeout: 2000,
        cleanup_interval: 500
      )

      assert {:error, errors} = Jidoka.Config.validate_all()
      assert Enum.any?(errors, &String.contains?(&1, "SPARQL"))
    end

    test "returns errors when session values are invalid" do
      Application.put_env(:jidoka, :llm,
        provider: :mock,
        model: "test-model"
      )

      Application.put_env(:jidoka, :knowledge_graph, backend: :native)

      Application.put_env(:jidoka, :session,
        max_sessions: -1,
        idle_timeout: 1000,
        absolute_timeout: 2000,
        cleanup_interval: 500
      )

      assert {:error, errors} = Jidoka.Config.validate_all()
      assert Enum.any?(errors, &String.contains?(&1, "Max sessions"))
    end
  end

  describe "llm_provider/0" do
    test "returns the configured LLM provider" do
      Application.put_env(:jidoka, :llm, provider: :anthropic)
      assert Jidoka.Config.llm_provider() == :anthropic
    end

    test "returns :none when not configured" do
      Application.put_env(:jidoka, :llm, [])
      assert Jidoka.Config.llm_provider() == :none
    end
  end

  describe "llm_model/0" do
    test "returns the configured LLM model" do
      Application.put_env(:jidoka, :llm, model: "gpt-4-turbo")
      assert Jidoka.Config.llm_model() == "gpt-4-turbo"
    end

    test "returns default model when not configured" do
      Application.put_env(:jidoka, :llm, [])
      assert Jidoka.Config.llm_model() == "gpt-4"
    end
  end

  describe "llm_api_key/0" do
    test "returns the API key when configured with SecureCredentials" do
      # Set provider to mock
      Application.put_env(:jidoka, :llm, provider: :mock)
      # Mock provider returns a predefined key
      assert {:ok, "mock-api-key"} = Jidoka.Config.llm_api_key()
    end

    test "returns :error when provider is :none" do
      Application.put_env(:jidoka, :llm, provider: :none)
      assert :error = Jidoka.Config.llm_api_key()
    end

    test "returns SecureCredentials result for valid provider" do
      # Set provider and put key in SecureCredentials
      Application.put_env(:jidoka, :llm, provider: :openai)
      Jidoka.SecureCredentials.put_api_key(:openai, "sk-test-key-from-config")
      assert {:ok, "sk-test-key-from-config"} = Jidoka.Config.llm_api_key()
    end
  end

  describe "llm_max_tokens/0" do
    test "returns the configured max tokens" do
      Application.put_env(:jidoka, :llm, max_tokens: 8192)
      assert Jidoka.Config.llm_max_tokens() == 8192
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :llm, [])
      assert Jidoka.Config.llm_max_tokens() == 4096
    end
  end

  describe "llm_temperature/0" do
    test "returns the configured temperature" do
      Application.put_env(:jidoka, :llm, temperature: 0.5)
      assert Jidoka.Config.llm_temperature() == 0.5
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :llm, [])
      assert Jidoka.Config.llm_temperature() == 0.7
    end
  end

  describe "llm_request_timeout/0" do
    test "returns the configured request timeout" do
      Application.put_env(:jidoka, :llm, request_timeout: 120_000)
      assert Jidoka.Config.llm_request_timeout() == 120_000
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :llm, [])
      assert Jidoka.Config.llm_request_timeout() == 60_000
    end
  end

  describe "knowledge_backend/0" do
    test "returns the configured backend" do
      Application.put_env(:jidoka, :knowledge_graph, backend: :remote_sparql)
      assert Jidoka.Config.knowledge_backend() == :remote_sparql
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :knowledge_graph, [])
      assert Jidoka.Config.knowledge_backend() == :native
    end
  end

  describe "sparql_endpoint/0" do
    test "returns the configured endpoint" do
      Application.put_env(:jidoka, :knowledge_graph,
        sparql_endpoint: "http://example.com/sparql"
      )

      assert Jidoka.Config.sparql_endpoint() == "http://example.com/sparql"
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :knowledge_graph, [])
      assert Jidoka.Config.sparql_endpoint() == "http://localhost:8080/sparql"
    end
  end

  describe "knowledge_cache_enabled?/0" do
    test "returns the cache enabled setting" do
      Application.put_env(:jidoka, :knowledge_graph, cache_enabled: false)
      refute Jidoka.Config.knowledge_cache_enabled?()
    end

    test "returns true by default" do
      Application.put_env(:jidoka, :knowledge_graph, [])
      assert Jidoka.Config.knowledge_cache_enabled?()
    end
  end

  describe "knowledge_max_cache_size/0" do
    test "returns the configured max cache size" do
      Application.put_env(:jidoka, :knowledge_graph, max_cache_size: 50_000)
      assert Jidoka.Config.knowledge_max_cache_size() == 50_000
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :knowledge_graph, [])
      assert Jidoka.Config.knowledge_max_cache_size() == 10_000
    end
  end

  describe "knowledge_cache_ttl/0" do
    test "returns the configured cache TTL" do
      Application.put_env(:jidoka, :knowledge_graph, cache_ttl: 600_000)
      assert Jidoka.Config.knowledge_cache_ttl() == 600_000
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :knowledge_graph, [])
      assert Jidoka.Config.knowledge_cache_ttl() == 300_000
    end
  end

  describe "max_sessions/0" do
    test "returns the configured max sessions" do
      Application.put_env(:jidoka, :session, max_sessions: 500)
      assert Jidoka.Config.max_sessions() == 500
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :session, [])
      assert Jidoka.Config.max_sessions() == 100
    end
  end

  describe "session_idle_timeout/0" do
    test "returns the configured idle timeout" do
      Application.put_env(:jidoka, :session, idle_timeout: 600_000)
      assert Jidoka.Config.session_idle_timeout() == 600_000
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :session, [])
      assert Jidoka.Config.session_idle_timeout() == 300_000
    end
  end

  describe "session_absolute_timeout/0" do
    test "returns the configured absolute timeout" do
      Application.put_env(:jidoka, :session, absolute_timeout: 7_200_000)
      assert Jidoka.Config.session_absolute_timeout() == 7_200_000
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :session, [])
      assert Jidoka.Config.session_absolute_timeout() == 3_600_000
    end
  end

  describe "session_cleanup_interval/0" do
    test "returns the configured cleanup interval" do
      Application.put_env(:jidoka, :session, cleanup_interval: 120_000)
      assert Jidoka.Config.session_cleanup_interval() == 120_000
    end

    test "returns default when not configured" do
      Application.put_env(:jidoka, :session, [])
      assert Jidoka.Config.session_cleanup_interval() == 60_000
    end
  end

  describe "operation_timeout/0" do
    test "returns the configured operation timeout" do
      Application.put_env(:jidoka, :operation_timeout, 45_000)
      assert Jidoka.Config.operation_timeout() == 45_000
    end

    test "returns default when not configured" do
      Application.delete_env(:jidoka, :operation_timeout)
      assert Jidoka.Config.operation_timeout() == 30_000
    end
  end

  describe "telemetry_enabled?/0" do
    test "returns the telemetry enabled setting" do
      Application.put_env(:jidoka, :enable_telemetry, false)
      refute Jidoka.Config.telemetry_enabled?()
    end

    test "returns true by default" do
      Application.delete_env(:jidoka, :enable_telemetry)
      assert Jidoka.Config.telemetry_enabled?()
    end
  end
end
