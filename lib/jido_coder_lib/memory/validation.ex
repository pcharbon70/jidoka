defmodule JidoCoderLib.Memory.Validation do
  @moduledoc """
  Shared validation functions for memory operations.

  All validators return `:ok | {:error, reason}` for consistency.
  Use `with` for multi-step validation flows.

  ## Examples

      with :ok <- Validation.validate_required_fields(item),
           :ok <- Validation.validate_memory_size(item.data) do
        # Proceed with operation
      end
  """

  @type validation_result :: :ok | {:error, term()}

  # Configuration constants
  @max_memory_size_bytes 100 * 1024
  @max_string_length 10_000
  @max_session_id_length 256

  # Valid memory types
  @valid_types [
    :fact,
    :decision,
    :assumption,
    :analysis,
    :conversation,
    :file_context,
    :lesson_learned
  ]

  @doc """
  Validates that required fields exist in the given map.

  ## Parameters
  - item: The map to validate
  - required: List of required field atoms (defaults to standard memory fields)

  ## Returns
  - `:ok` if all required fields are present
  - `{:error, {:missing_fields, fields}}` if any are missing

  ## Examples

      iex> Validation.validate_required_fields(%{id: "1", type: :fact, data: %{}, importance: 0.5})
      :ok

      iex> Validation.validate_required_fields(%{id: "1"})
      {:error, {:missing_fields, [:type, :data, :importance]}}
  """
  @spec validate_required_fields(map(), [atom()]) :: validation_result()
  def validate_required_fields(item, required \\ [:id, :type, :data, :importance]) do
    missing = Enum.reject(required, &Map.has_key?(item, &1))

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_fields, fields}}
    end
  end

  @doc """
  Validates that memory data size is within limits (100KB max).

  Uses `:erlang.external_size/1` to measure actual term size,
  accounting for nested structures and overhead.

  ## Parameters
  - data: The data map to validate

  ## Returns
  - `:ok` if size is within limits
  - `{:error, {:data_too_large, size, max}}` if too large

  ## Examples

      iex> Validation.validate_memory_size(%{"key" => "value"})
      :ok

  For large data exceeding 100KB, returns `{:error, {:data_too_large, size, max}}`.

  """
  @spec validate_memory_size(map() | nil) :: validation_result()
  def validate_memory_size(nil), do: :ok

  def validate_memory_size(data) when is_map(data) do
    size = :erlang.external_size({data})

    if size <= @max_memory_size_bytes do
      :ok
    else
      {:error, {:data_too_large, size, @max_memory_size_bytes}}
    end
  end

  def validate_memory_size(_), do: {:error, :invalid_data_type}

  @doc """
  Validates that a string field length is within limits.

  ## Parameters
  - value: The string to validate

  ## Returns
  - `:ok` if within limits
  - `{:error, {:string_too_long, length, max}}` if too long
  """
  @spec validate_string_length(binary()) :: validation_result()
  def validate_string_length(value) when is_binary(value) do
    if byte_size(value) <= @max_string_length do
      :ok
    else
      {:error, {:string_too_long, byte_size(value), @max_string_length}}
    end
  end

  @doc """
  Validates that importance score is between 0.0 and 1.0.

  ## Parameters
  - importance: The importance score to validate

  ## Returns
  - `:ok` if valid
  - `{:error, {:invalid_importance, value}}` if invalid
  """
  @spec validate_importance(float()) :: validation_result()
  def validate_importance(importance) when is_float(importance) do
    if importance >= 0.0 and importance <= 1.0 do
      :ok
    else
      {:error, {:invalid_importance, importance}}
    end
  end

  def validate_importance(_), do: {:error, {:invalid_importance, :not_a_float}}

  @doc """
  Validates that memory type is one of the allowed atoms.

  Valid types: :fact, :decision, :assumption, :analysis, :conversation,
              :file_context, :lesson_learned

  ## Parameters
  - type: The type atom to validate

  ## Returns
  - `:ok` if valid
  - `{:error, {:invalid_type, type}}` if invalid
  """
  @spec validate_type(atom()) :: validation_result()
  def validate_type(type) when type in @valid_types, do: :ok
  def validate_type(type), do: {:error, {:invalid_type, type}}

  @doc """
  Validates that session_id is a non-empty binary within length limits.

  ## Parameters
  - id: The session_id to validate

  ## Returns
  - `:ok` if valid
  - `:error, :invalid_session_id` if invalid
  """
  @spec validate_session_id(binary()) :: validation_result()
  def validate_session_id(id) when is_binary(id) and byte_size(id) > 0 do
    if byte_size(id) <= @max_session_id_length do
      :ok
    else
      {:error, {:session_id_too_long, byte_size(id), @max_session_id_length}}
    end
  end

  def validate_session_id(_), do: {:error, :invalid_session_id}

  @doc """
  Validates a message map for the conversation buffer.

  ## Parameters
  - message: The message map to validate

  ## Returns
  - `:ok` if valid
  - `{:error, reason}` if invalid
  """
  @spec validate_message(map()) :: validation_result()
  def validate_message(message) when is_map(message) do
    with :ok <- validate_field(message, :role),
         :ok <- validate_field(message, :content) do
      validate_string_length(Map.get(message, :content, ""))
    end
  end

  def validate_message(_), do: {:error, :invalid_message_format}

  @doc """
  Validates that a specific field exists in a map.

  ## Parameters
  - item: The map to check
  - field: The field atom to check for

  ## Returns
  - `:ok` if field exists
  - `{:error, {:missing_field, field}}` if missing
  """
  @spec validate_field(map(), atom()) :: validation_result()
  def validate_field(item, field) when is_map(item) do
    if Map.has_key?(item, field) do
      :ok
    else
      {:error, {:missing_field, field}}
    end
  end

  def validate_field(_, _), do: {:error, :not_a_map}

  @doc """
  Validates all memory constraints in a single call.

  Checks: required fields, data size, importance, type, session_id

  ## Parameters
  - item: The memory map to validate

  ## Returns
  - `{:ok, item}` if all validations pass
  - `{:error, reason}` if any validation fails

  ## Examples

      iex> item = %{id: "1", type: :fact, data: %{}, importance: 0.5, session_id: "session_123"}
      iex> Validation.validate_memory(item)
      {:ok, item}

      iex> Validation.validate_memory(%{id: "1"})
      {:error, {:missing_fields, [:type, :data, :importance]}}
  """
  @spec validate_memory(map()) :: {:ok, map()} | {:error, term()}
  def validate_memory(item) when is_map(item) do
    with :ok <- validate_required_fields(item),
         :ok <- validate_memory_size(Map.get(item, :data, %{})),
         :ok <- validate_importance(Map.get(item, :importance)),
         :ok <- validate_type(Map.get(item, :type)),
         :ok <- validate_session_id(Map.get(item, :session_id)) do
      {:ok, item}
    end
  end

  def validate_memory(_), do: {:error, :not_a_map}

  @doc """
  Validates session configuration options.

  ## Parameters
  - opts: Keyword list of options

  ## Returns
  - `:ok` if valid
  - `{:error, :invalid_session_opts}` if invalid
  """
  @spec validate_session_opts(keyword()) :: validation_result()
  def validate_session_opts(opts) when is_list(opts) do
    max_messages = Keyword.get(opts, :max_messages, 100)
    max_tokens = Keyword.get(opts, :max_tokens, 4000)
    max_context_items = Keyword.get(opts, :max_context_items, 50)

    with true <- is_integer(max_messages) and max_messages > 0,
         true <- is_integer(max_tokens) and max_tokens > 0,
         true <- is_integer(max_context_items) and max_context_items >= 0 do
      :ok
    else
      _ -> {:error, :invalid_session_opts}
    end
  end

  def validate_session_opts(_), do: {:error, :invalid_session_opts}

  @doc """
  Checks if a result is an OK validation result.

  ## Examples

      iex> Validation.ok?(:ok)
      true

      iex> Validation.ok?({:error, :reason})
      false
  """
  @spec ok?(validation_result()) :: boolean()
  def ok?(:ok), do: true
  def ok?(_), do: false

  @doc """
  Checks if a result is an error validation result.

  ## Examples

      iex> Validation.error?({:error, :reason})
      true

      iex> Validation.error?(:ok)
      false
  """
  @spec error?(validation_result()) :: boolean()
  def error?({:error, _}), do: true
  def error?(_), do: false

  @doc """
  Returns the list of valid memory types.

  ## Examples

      iex> is_list(Validation.valid_types())
      true
  """
  @spec valid_types() :: [atom()]
  def valid_types, do: @valid_types

  @doc """
  Returns the maximum memory size in bytes.

  ## Examples

      iex> is_integer(Validation.max_memory_size_bytes())
      true
      iex> Validation.max_memory_size_bytes() > 0
      true
  """
  @spec max_memory_size_bytes() :: pos_integer()
  def max_memory_size_bytes, do: @max_memory_size_bytes
end
