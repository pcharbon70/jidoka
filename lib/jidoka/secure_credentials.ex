defmodule Jidoka.SecureCredentials do
  @moduledoc """
  Secure credential storage with restricted access.

  This module uses a GenServer with a private ETS table to store
  sensitive credentials like API keys. Only this module can access
  the credentials, preventing accidental exposure through
  `Application.get_env/3`.

  ## Security Features

  - Private ETS table (only this GenServer can access)
  - API key format validation per provider
  - Loaded from environment at startup
  - No direct access to credentials from other processes

  ## Examples

      # Get an API key (returns {:ok, key} or :error)
      {:ok, key} = Jidoka.SecureCredentials.get_api_key(:openai)

      # Put an API key (for testing or runtime updates)
      :ok = Jidoka.SecureCredentials.put_api_key(:openai, "sk-...")

  """

  use GenServer
  @table_name :jido_secure_credentials

  #
  # Client API
  #

  @doc """
  Starts the SecureCredentials GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Retrieves an API key for the given provider.

  ## Parameters

  * `provider` - The provider atom (e.g., :openai, :anthropic)

  ## Returns

  * `{:ok, key}` - If the key exists
  * `:error` - If the key is not found

  ## Examples

      iex> Jidoka.SecureCredentials.put_api_key(:openai, "sk-test-key")
      iex> Jidoka.SecureCredentials.get_api_key(:openai)
      {:ok, "sk-test-key"}

      iex> Jidoka.SecureCredentials.get_api_key(:unknown)
      :error

  """
  @spec get_api_key(atom()) :: {:ok, String.t()} | :error
  def get_api_key(provider) when is_atom(provider) do
    GenServer.call(__MODULE__, {:get_key, provider})
  end

  @doc """
  Stores an API key for the given provider.

  ## Parameters

  * `provider` - The provider atom (e.g., :openai, :anthropic)
  * `key` - The API key string

  ## Returns

  * `:ok` - If the key was stored
  * `{:error, :invalid_key}` - If the key format is invalid

  ## Examples

      iex> Jidoka.SecureCredentials.put_api_key(:openai, "sk-...")
      :ok

  """
  @spec put_api_key(atom(), String.t()) :: :ok | {:error, atom()}
  def put_api_key(provider, key) when is_atom(provider) and is_binary(key) do
    GenServer.call(__MODULE__, {:put_key, provider, key})
  end

  def put_api_key(_provider, _key), do: {:error, :invalid_key}

  @doc """
  Deletes an API key for the given provider.

  ## Parameters

  * `provider` - The provider atom

  ## Returns

  * `:ok` - If the key was deleted (or didn't exist)

  ## Examples

      iex> Jidoka.SecureCredentials.delete_api_key(:openai)
      :ok

  """
  @spec delete_api_key(atom()) :: :ok
  def delete_api_key(provider) when is_atom(provider) do
    GenServer.call(__MODULE__, {:delete_key, provider})
  end

  @doc """
  Clears all stored API keys.

  This is primarily intended for testing purposes.

  ## Returns

  * `:ok` - Always succeeds

  ## Examples

      Jidoka.SecureCredentials.clear_all()

  """
  @spec clear_all() :: :ok
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  #
  # Server Callbacks
  #

  @impl true
  def init(_opts) do
    # Create private ETS table (only this GenServer can access)
    :ets.new(@table_name, [:set, :private, :named_table])

    # Load keys from environment at startup
    load_keys_from_env()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:put_key, provider, key}, _from, state) do
    if valid_key?(provider, key) do
      :ets.insert(@table_name, {provider, key})
      {:reply, :ok, state}
    else
      {:reply, {:error, :invalid_key}, state}
    end
  end

  @impl true
  def handle_call({:get_key, provider}, _from, state) do
    case :ets.lookup(@table_name, provider) do
      [{^provider, key}] -> {:reply, {:ok, key}, state}
      [] -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:delete_key, provider}, _from, state) do
    :ets.delete(@table_name, provider)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:clear_all, _from, state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:ping, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  #
  # Private Functions
  #

  defp load_keys_from_env do
    # Load keys from config at startup
    env_keys = Application.get_env(:jidoka, :api_keys, [])

    Enum.each(env_keys, fn {provider, key} when is_atom(provider) and is_binary(key) ->
      if valid_key?(provider, key) do
        :ets.insert(@table_name, {provider, key})
      end
    end)
  end

  # API key format validation
  defp valid_key?(:openai, key), do: String.starts_with?(key, "sk-")
  defp valid_key?(:anthropic, key), do: String.starts_with?(key, "sk-ant-")
  defp valid_key?(:google, key), do: String.starts_with?(key, "AIza")
  defp valid_key?(:cohere, key), do: String.starts_with?(key, "cohere-")

  defp valid_key?(provider, key) when is_atom(provider) and is_binary(key) do
    # For unknown providers, just check basic requirements
    is_binary(key) and byte_size(key) > 20
  end
end
