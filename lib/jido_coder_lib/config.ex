defmodule JidoCoderLib.Config do
  @moduledoc """
  Configuration validation and helper module for JidoCoderLib.

  This module provides functions to validate and retrieve configuration
  values for the application. It centralizes configuration access and
  provides helpful error messages when configuration is missing or invalid.

  ## Configuration Sections

  ### LLM Configuration

      JidoCoderLib.Config.llm_provider()
      # => :openai | :anthropic | :ollama | :mock | :none

      JidoCoderLib.Config.llm_model()
      # => "gpt-4"

      JidoCoderLib.Config.llm_api_key()
      # => "sk-..." or :error

  ### Knowledge Graph Configuration

      JidoCoderLib.Config.knowledge_backend()
      # => :native | :remote_sparql

      JidoCoderLib.Config.sparql_endpoint()
      # => "http://localhost:8080/sparql"

  ### Session Configuration

      JidoCoderLib.Config.max_sessions()
      # => 100

      JidoCoderLib.Config.session_idle_timeout()
      # => 300_000 (5 minutes)

  ## Examples

  Validate all configuration at startup:

      case JidoCoderLib.Config.validate_all() do
        :ok -> # Application can start
        {:error, errors} -> # Handle configuration errors
      end

  Get a specific configuration value:

      provider = JidoCoderLib.Config.llm_provider()

  """

  @doc """
  Validates all configuration sections.

  Returns `:ok` if all configuration is valid, or `{:error, errors}` where
  errors is a list of error messages describing configuration problems.

  ## Examples

      iex> JidoCoderLib.Config.validate_all()
      :ok

      iex> JidoCoderLib.Config.validate_all()
      {:error, ["LLM provider is not configured"]}

  """
  def validate_all do
    errors =
      []
      |> validate_llm_config()
      |> validate_knowledge_graph_config()
      |> validate_session_config()

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @doc """
  Returns the configured LLM provider.

  ## Examples

      iex> JidoCoderLib.Config.llm_provider()
      :openai

  """
  def llm_provider do
    Application.get_env(:jido_coder_lib, :llm, [])
    |> Keyword.get(:provider, :none)
  end

  @doc """
  Returns the configured LLM model.

  ## Examples

      iex> JidoCoderLib.Config.llm_model()
      "gpt-4"

  """
  def llm_model do
    Application.get_env(:jido_coder_lib, :llm, [])
    |> Keyword.get(:model, "gpt-4")
  end

  @doc """
  Returns the configured LLM API key.

  Returns `:error` if the API key is not configured.

  ## Security

  The API key is retrieved from SecureCredentials, which uses a private
  ETS table accessible only to its GenServer. This prevents other
  processes from accessing sensitive credentials.

  ## Examples

      iex> JidoCoderLib.Config.llm_api_key()
      {:ok, "sk-..."}

      iex> JidoCoderLib.Config.llm_api_key()
      :error

  """
  @spec llm_api_key() :: {:ok, String.t()} | :error
  def llm_api_key do
    provider = llm_provider()

    case provider do
      :none -> :error
      :mock -> {:ok, "mock-api-key"}
      _ -> JidoCoderLib.SecureCredentials.get_api_key(provider)
    end
  end

  @doc """
  Returns the LLM max tokens configuration.

  ## Examples

      iex> JidoCoderLib.Config.llm_max_tokens()
      4096

  """
  def llm_max_tokens do
    Application.get_env(:jido_coder_lib, :llm, [])
    |> Keyword.get(:max_tokens, 4096)
  end

  @doc """
  Returns the LLM temperature configuration.

  ## Examples

      iex> JidoCoderLib.Config.llm_temperature()
      0.7

  """
  def llm_temperature do
    Application.get_env(:jido_coder_lib, :llm, [])
    |> Keyword.get(:temperature, 0.7)
  end

  @doc """
  Returns the LLM request timeout in milliseconds.

  ## Examples

      iex> JidoCoderLib.Config.llm_request_timeout()
      60_000

  """
  def llm_request_timeout do
    Application.get_env(:jido_coder_lib, :llm, [])
    |> Keyword.get(:request_timeout, 60_000)
  end

  @doc """
  Returns the knowledge graph backend.

  ## Examples

      iex> JidoCoderLib.Config.knowledge_backend()
      :native

  """
  def knowledge_backend do
    Application.get_env(:jido_coder_lib, :knowledge_graph, [])
    |> Keyword.get(:backend, :native)
  end

  @doc """
  Returns the SPARQL endpoint URL.

  ## Examples

      iex> JidoCoderLib.Config.sparql_endpoint()
      "http://localhost:8080/sparql"

  """
  def sparql_endpoint do
    Application.get_env(:jido_coder_lib, :knowledge_graph, [])
    |> Keyword.get(:sparql_endpoint, "http://localhost:8080/sparql")
  end

  @doc """
  Returns whether knowledge graph caching is enabled.

  ## Examples

      iex> JidoCoderLib.Config.knowledge_cache_enabled?()
      true

  """
  def knowledge_cache_enabled? do
    Application.get_env(:jido_coder_lib, :knowledge_graph, [])
    |> Keyword.get(:cache_enabled, true)
  end

  @doc """
  Returns the maximum knowledge graph cache size.

  ## Examples

      iex> JidoCoderLib.Config.knowledge_max_cache_size()
      10_000

  """
  def knowledge_max_cache_size do
    Application.get_env(:jido_coder_lib, :knowledge_graph, [])
    |> Keyword.get(:max_cache_size, 10_000)
  end

  @doc """
  Returns the knowledge graph cache TTL in milliseconds.

  ## Examples

      iex> JidoCoderLib.Config.knowledge_cache_ttl()
      300_000

  """
  def knowledge_cache_ttl do
    Application.get_env(:jido_coder_lib, :knowledge_graph, [])
    |> Keyword.get(:cache_ttl, 300_000)
  end

  @doc """
  Returns the maximum number of concurrent sessions.

  ## Examples

      iex> JidoCoderLib.Config.max_sessions()
      100

  """
  def max_sessions do
    Application.get_env(:jido_coder_lib, :session, [])
    |> Keyword.get(:max_sessions, 100)
  end

  @doc """
  Returns the session idle timeout in milliseconds.

  ## Examples

      iex> JidoCoderLib.Config.session_idle_timeout()
      300_000

  """
  def session_idle_timeout do
    Application.get_env(:jido_coder_lib, :session, [])
    |> Keyword.get(:idle_timeout, 300_000)
  end

  @doc """
  Returns the session absolute timeout in milliseconds.

  ## Examples

      iex> JidoCoderLib.Config.session_absolute_timeout()
      3_600_000

  """
  def session_absolute_timeout do
    Application.get_env(:jido_coder_lib, :session, [])
    |> Keyword.get(:absolute_timeout, 3_600_000)
  end

  @doc """
  Returns the session cleanup interval in milliseconds.

  ## Examples

      iex> JidoCoderLib.Config.session_cleanup_interval()
      60_000

  """
  def session_cleanup_interval do
    Application.get_env(:jido_coder_lib, :session, [])
    |> Keyword.get(:cleanup_interval, 60_000)
  end

  @doc """
  Returns the operation timeout in milliseconds.

  ## Examples

      iex> JidoCoderLib.Config.operation_timeout()
      30_000

  """
  def operation_timeout do
    Application.get_env(:jido_coder_lib, :operation_timeout, 30_000)
  end

  @doc """
  Returns whether telemetry is enabled.

  ## Examples

      iex> JidoCoderLib.Config.telemetry_enabled?()
      true

  """
  def telemetry_enabled? do
    Application.get_env(:jido_coder_lib, :enable_telemetry, true)
  end

  # Private functions

  defp validate_llm_config(errors) do
    provider = llm_provider()

    errors
    |> validate_required(
      provider in [:openai, :anthropic, :ollama, :mock, :none],
      "LLM provider must be one of: :openai, :anthropic, :ollama, :mock, :none, got: #{inspect(provider)}"
    )
    |> validate_required(
      is_binary(llm_model()) and llm_model() != "",
      "LLM model must be configured as a non-empty string"
    )
    |> validate_when(
      provider in [:openai, :anthropic, :google, :cohere] and provider != :mock,
      llm_api_key() != :error,
      "LLM API key is required for provider #{inspect(provider)}"
    )
  end

  defp validate_knowledge_graph_config(errors) do
    backend = knowledge_backend()

    errors
    |> validate_required(
      backend in [:native, :remote_sparql],
      "Knowledge graph backend must be :native or :remote_sparql, got: #{inspect(backend)}"
    )
    |> validate_when(
      backend == :remote_sparql,
      is_binary(sparql_endpoint()) and sparql_endpoint() != "",
      "SPARQL endpoint must be configured when using remote_sparql backend"
    )
  end

  defp validate_session_config(errors) do
    errors
    |> validate_positive(max_sessions(), "Max sessions must be positive")
    |> validate_positive(session_idle_timeout(), "Session idle timeout must be positive")
    |> validate_positive(session_absolute_timeout(), "Session absolute timeout must be positive")
    |> validate_positive(session_cleanup_interval(), "Session cleanup interval must be positive")
  end

  defp validate_required(errors, true, _message), do: errors
  defp validate_required(errors, false, message), do: [message | errors]

  defp validate_when(errors, true, true, _message), do: errors
  defp validate_when(errors, true, false, message), do: [message | errors]
  defp validate_when(errors, false, _condition, _message), do: errors

  defp validate_positive(errors, value, _message) when is_number(value) and value > 0, do: errors
  defp validate_positive(errors, _value, message), do: [message | errors]
end
