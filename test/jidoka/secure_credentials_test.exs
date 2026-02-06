defmodule Jidoka.SecureCredentialsTest do
  use ExUnit.Case, async: false

  @moduletag :secure_credentials

  doctest Jidoka.SecureCredentials

  setup do
    # Clear all keys before each test for isolation
    Jidoka.SecureCredentials.clear_all()
    :ok
  end

  describe "get_api_key/1" do
    test "returns {:ok, key} when key exists" do
      Jidoka.SecureCredentials.put_api_key(:openai, "sk-test-key-12345")

      assert {:ok, "sk-test-key-12345"} = Jidoka.SecureCredentials.get_api_key(:openai)
    end

    test "returns :error when key does not exist" do
      assert :error = Jidoka.SecureCredentials.get_api_key(:nonexistent)
    end

    test "validates key format for openai" do
      Jidoka.SecureCredentials.put_api_key(:openai, "sk-valid-key")
      assert {:ok, "sk-valid-key"} = Jidoka.SecureCredentials.get_api_key(:openai)

      # Invalid format - should not be stored
      assert {:error, :invalid_key} =
               Jidoka.SecureCredentials.put_api_key(:openai, "invalid-key")

      # Original key should still be accessible
      assert {:ok, "sk-valid-key"} = Jidoka.SecureCredentials.get_api_key(:openai)
    end

    test "validates key format for anthropic" do
      assert {:error, :invalid_key} =
               Jidoka.SecureCredentials.put_api_key(:anthropic, "invalid-key")

      assert :ok = Jidoka.SecureCredentials.put_api_key(:anthropic, "sk-ant-test-key")
      assert {:ok, "sk-ant-test-key"} = Jidoka.SecureCredentials.get_api_key(:anthropic)
    end

    test "validates key format for google" do
      assert :ok = Jidoka.SecureCredentials.put_api_key(:google, "AIzaTestKey")
      assert {:ok, "AIzaTestKey"} = Jidoka.SecureCredentials.get_api_key(:google)
    end

    test "validates key format for cohere" do
      assert :ok = Jidoka.SecureCredentials.put_api_key(:cohere, "cohere-test-key")
      assert {:ok, "cohere-test-key"} = Jidoka.SecureCredentials.get_api_key(:cohere)
    end

    test "allows unknown providers with sufficient key length" do
      assert :ok =
               Jidoka.SecureCredentials.put_api_key(
                 :unknown_provider,
                 "this-is-a-long-enough-key-12345"
               )

      assert {:ok, "this-is-a-long-enough-key-12345"} =
               Jidoka.SecureCredentials.get_api_key(:unknown_provider)
    end

    test "rejects short keys for unknown providers" do
      assert {:error, :invalid_key} =
               Jidoka.SecureCredentials.put_api_key(:unknown, "short")
    end
  end

  describe "put_api_key/2" do
    test "stores a valid key" do
      assert :ok = Jidoka.SecureCredentials.put_api_key(:openai, "sk-new-key")
      assert {:ok, "sk-new-key"} = Jidoka.SecureCredentials.get_api_key(:openai)
    end

    test "overwrites existing key" do
      assert :ok = Jidoka.SecureCredentials.put_api_key(:openai, "sk-first-key")
      assert :ok = Jidoka.SecureCredentials.put_api_key(:openai, "sk-second-key")
      assert {:ok, "sk-second-key"} = Jidoka.SecureCredentials.get_api_key(:openai)
    end

    test "returns {:error, :invalid_key} for invalid keys" do
      assert {:error, :invalid_key} =
               Jidoka.SecureCredentials.put_api_key(:openai, "invalid-format")
    end

    test "validates provider is an atom" do
      assert {:error, :invalid_key} =
               Jidoka.SecureCredentials.put_api_key("string_provider", "sk-key")
    end
  end

  describe "delete_api_key/1" do
    test "removes an existing key" do
      assert :ok = Jidoka.SecureCredentials.put_api_key(:openai, "sk-to-delete")
      assert {:ok, "sk-to-delete"} = Jidoka.SecureCredentials.get_api_key(:openai)

      assert :ok = Jidoka.SecureCredentials.delete_api_key(:openai)
      assert :error = Jidoka.SecureCredentials.get_api_key(:openai)
    end

    test "returns :ok when deleting non-existent key" do
      assert :ok = Jidoka.SecureCredentials.delete_api_key(:nonexistent)
    end
  end

  describe "security" do
    test "private ETS table is only accessible through GenServer" do
      # The ETS table exists but is private to the GenServer
      assert :ets.whereis(:jido_secure_credentials) != :undefined

      # Keys are accessed through the API, not direct ETS access
      # Use a key long enough for the unknown provider validation
      assert :ok =
               Jidoka.SecureCredentials.put_api_key(
                 :test_provider,
                 "sk-test-config-long-enough"
               )

      assert {:ok, "sk-test-config-long-enough"} =
               Jidoka.SecureCredentials.get_api_key(:test_provider)
    end
  end

  describe "start_link/1" do
    test "GenServer is running" do
      # SecureCredentials is started by the application
      # Verify it's registered and running
      assert Process.whereis(Jidoka.SecureCredentials) != nil
      assert GenServer.call(Jidoka.SecureCredentials, :ping) == :ok
    end
  end

  describe "integration" do
    test "full workflow: put, get, delete" do
      # Put
      assert :ok = Jidoka.SecureCredentials.put_api_key(:openai, "sk-workflow-test")

      # Get
      assert {:ok, "sk-workflow-test"} =
               Jidoka.SecureCredentials.get_api_key(:openai)

      # Update
      assert :ok = Jidoka.SecureCredentials.put_api_key(:openai, "sk-updated-key")
      assert {:ok, "sk-updated-key"} = Jidoka.SecureCredentials.get_api_key(:openai)

      # Delete
      assert :ok = Jidoka.SecureCredentials.delete_api_key(:openai)
      assert :error = Jidoka.SecureCredentials.get_api_key(:openai)
    end

    test "multiple providers coexist" do
      assert :ok = Jidoka.SecureCredentials.put_api_key(:openai, "sk-openai-key")
      assert :ok = Jidoka.SecureCredentials.put_api_key(:anthropic, "sk-ant-anthropic-key")
      assert :ok = Jidoka.SecureCredentials.put_api_key(:google, "AIzaGoogleKey")

      assert {:ok, "sk-openai-key"} = Jidoka.SecureCredentials.get_api_key(:openai)

      assert {:ok, "sk-ant-anthropic-key"} =
               Jidoka.SecureCredentials.get_api_key(:anthropic)

      assert {:ok, "AIzaGoogleKey"} = Jidoka.SecureCredentials.get_api_key(:google)

      # Deleting one should not affect others
      assert :ok = Jidoka.SecureCredentials.delete_api_key(:anthropic)
      assert {:ok, "sk-openai-key"} = Jidoka.SecureCredentials.get_api_key(:openai)
      assert :error = Jidoka.SecureCredentials.get_api_key(:anthropic)
      assert {:ok, "AIzaGoogleKey"} = Jidoka.SecureCredentials.get_api_key(:google)
    end
  end
end
