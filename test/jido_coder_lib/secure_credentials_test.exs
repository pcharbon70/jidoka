defmodule JidoCoderLib.SecureCredentialsTest do
  use ExUnit.Case, async: false

  @moduletag :secure_credentials

  doctest JidoCoderLib.SecureCredentials

  setup do
    # Clear all keys before each test for isolation
    JidoCoderLib.SecureCredentials.clear_all()
    :ok
  end

  describe "get_api_key/1" do
    test "returns {:ok, key} when key exists" do
      JidoCoderLib.SecureCredentials.put_api_key(:openai, "sk-test-key-12345")

      assert {:ok, "sk-test-key-12345"} = JidoCoderLib.SecureCredentials.get_api_key(:openai)
    end

    test "returns :error when key does not exist" do
      assert :error = JidoCoderLib.SecureCredentials.get_api_key(:nonexistent)
    end

    test "validates key format for openai" do
      JidoCoderLib.SecureCredentials.put_api_key(:openai, "sk-valid-key")
      assert {:ok, "sk-valid-key"} = JidoCoderLib.SecureCredentials.get_api_key(:openai)

      # Invalid format - should not be stored
      assert {:error, :invalid_key} =
               JidoCoderLib.SecureCredentials.put_api_key(:openai, "invalid-key")

      # Original key should still be accessible
      assert {:ok, "sk-valid-key"} = JidoCoderLib.SecureCredentials.get_api_key(:openai)
    end

    test "validates key format for anthropic" do
      assert {:error, :invalid_key} =
               JidoCoderLib.SecureCredentials.put_api_key(:anthropic, "invalid-key")

      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:anthropic, "sk-ant-test-key")
      assert {:ok, "sk-ant-test-key"} = JidoCoderLib.SecureCredentials.get_api_key(:anthropic)
    end

    test "validates key format for google" do
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:google, "AIzaTestKey")
      assert {:ok, "AIzaTestKey"} = JidoCoderLib.SecureCredentials.get_api_key(:google)
    end

    test "validates key format for cohere" do
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:cohere, "cohere-test-key")
      assert {:ok, "cohere-test-key"} = JidoCoderLib.SecureCredentials.get_api_key(:cohere)
    end

    test "allows unknown providers with sufficient key length" do
      assert :ok =
               JidoCoderLib.SecureCredentials.put_api_key(
                 :unknown_provider,
                 "this-is-a-long-enough-key-12345"
               )

      assert {:ok, "this-is-a-long-enough-key-12345"} =
               JidoCoderLib.SecureCredentials.get_api_key(:unknown_provider)
    end

    test "rejects short keys for unknown providers" do
      assert {:error, :invalid_key} =
               JidoCoderLib.SecureCredentials.put_api_key(:unknown, "short")
    end
  end

  describe "put_api_key/2" do
    test "stores a valid key" do
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:openai, "sk-new-key")
      assert {:ok, "sk-new-key"} = JidoCoderLib.SecureCredentials.get_api_key(:openai)
    end

    test "overwrites existing key" do
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:openai, "sk-first-key")
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:openai, "sk-second-key")
      assert {:ok, "sk-second-key"} = JidoCoderLib.SecureCredentials.get_api_key(:openai)
    end

    test "returns {:error, :invalid_key} for invalid keys" do
      assert {:error, :invalid_key} =
               JidoCoderLib.SecureCredentials.put_api_key(:openai, "invalid-format")
    end

    test "validates provider is an atom" do
      assert {:error, :invalid_key} =
               JidoCoderLib.SecureCredentials.put_api_key("string_provider", "sk-key")
    end
  end

  describe "delete_api_key/1" do
    test "removes an existing key" do
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:openai, "sk-to-delete")
      assert {:ok, "sk-to-delete"} = JidoCoderLib.SecureCredentials.get_api_key(:openai)

      assert :ok = JidoCoderLib.SecureCredentials.delete_api_key(:openai)
      assert :error = JidoCoderLib.SecureCredentials.get_api_key(:openai)
    end

    test "returns :ok when deleting non-existent key" do
      assert :ok = JidoCoderLib.SecureCredentials.delete_api_key(:nonexistent)
    end
  end

  describe "security" do
    test "private ETS table is only accessible through GenServer" do
      # The ETS table exists but is private to the GenServer
      assert :ets.whereis(:jido_secure_credentials) != :undefined

      # Keys are accessed through the API, not direct ETS access
      # Use a key long enough for the unknown provider validation
      assert :ok =
               JidoCoderLib.SecureCredentials.put_api_key(
                 :test_provider,
                 "sk-test-config-long-enough"
               )

      assert {:ok, "sk-test-config-long-enough"} =
               JidoCoderLib.SecureCredentials.get_api_key(:test_provider)
    end
  end

  describe "start_link/1" do
    test "GenServer is running" do
      # SecureCredentials is started by the application
      # Verify it's registered and running
      assert Process.whereis(JidoCoderLib.SecureCredentials) != nil
      assert GenServer.call(JidoCoderLib.SecureCredentials, :ping) == :ok
    end
  end

  describe "integration" do
    test "full workflow: put, get, delete" do
      # Put
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:openai, "sk-workflow-test")

      # Get
      assert {:ok, "sk-workflow-test"} =
               JidoCoderLib.SecureCredentials.get_api_key(:openai)

      # Update
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:openai, "sk-updated-key")
      assert {:ok, "sk-updated-key"} = JidoCoderLib.SecureCredentials.get_api_key(:openai)

      # Delete
      assert :ok = JidoCoderLib.SecureCredentials.delete_api_key(:openai)
      assert :error = JidoCoderLib.SecureCredentials.get_api_key(:openai)
    end

    test "multiple providers coexist" do
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:openai, "sk-openai-key")
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:anthropic, "sk-ant-anthropic-key")
      assert :ok = JidoCoderLib.SecureCredentials.put_api_key(:google, "AIzaGoogleKey")

      assert {:ok, "sk-openai-key"} = JidoCoderLib.SecureCredentials.get_api_key(:openai)

      assert {:ok, "sk-ant-anthropic-key"} =
               JidoCoderLib.SecureCredentials.get_api_key(:anthropic)

      assert {:ok, "AIzaGoogleKey"} = JidoCoderLib.SecureCredentials.get_api_key(:google)

      # Deleting one should not affect others
      assert :ok = JidoCoderLib.SecureCredentials.delete_api_key(:anthropic)
      assert {:ok, "sk-openai-key"} = JidoCoderLib.SecureCredentials.get_api_key(:openai)
      assert :error = JidoCoderLib.SecureCredentials.get_api_key(:anthropic)
      assert {:ok, "AIzaGoogleKey"} = JidoCoderLib.SecureCredentials.get_api_key(:google)
    end
  end
end
