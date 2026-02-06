defmodule Jidoka.Memory.ValidationTest do
  @moduledoc """
  Tests for the Validation module.
  """

  use ExUnit.Case, async: true
  alias Jidoka.Memory.Validation

  doctest Validation

  describe "validate_required_fields/2" do
    test "returns :ok when all required fields are present" do
      item = %{
        id: "test_id",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.8
      }

      assert Validation.validate_required_fields(item) == :ok
    end

    test "returns :ok when custom required fields are all present" do
      item = %{id: "test_id", name: "test"}
      assert Validation.validate_required_fields(item, [:id, :name]) == :ok
    end

    test "returns error when required fields are missing" do
      item = %{id: "test_id"}

      assert Validation.validate_required_fields(item) ==
               {:error, {:missing_fields, [:type, :data, :importance]}}
    end

    test "returns error when custom required fields are missing" do
      item = %{id: "test_id"}

      assert Validation.validate_required_fields(item, [:id, :name]) ==
               {:error, {:missing_fields, [:name]}}
    end

    test "returns error when item is not a map" do
      assert Validation.validate_field("not a map", :id) == {:error, :not_a_map}
    end
  end

  describe "validate_field/2" do
    test "returns :ok when field exists" do
      item = %{id: "test_id", type: :fact}
      assert Validation.validate_field(item, :id) == :ok
    end

    test "returns error when field is missing" do
      item = %{id: "test_id"}
      assert Validation.validate_field(item, :type) == {:error, {:missing_field, :type}}
    end

    test "returns error when item is not a map" do
      assert Validation.validate_field("not a map", :id) == {:error, :not_a_map}
    end
  end

  describe "validate_memory_size/1" do
    test "returns :ok for small data maps" do
      data = %{"key" => "value"}
      assert Validation.validate_memory_size(data) == :ok
    end

    test "returns :ok for nested data maps within limit" do
      data = %{
        "level1" => %{
          "level2" => %{
            "level3" => List.duplicate(%{"item" => "data"}, 100)
          }
        }
      }

      assert Validation.validate_memory_size(data) == :ok
    end

    test "returns :ok for empty map" do
      assert Validation.validate_memory_size(%{}) == :ok
    end

    test "returns error for data exceeding 100KB" do
      # Create data larger than 100KB
      large_data =
        for i <- 1..2000, into: %{} do
          {"key_#{i}", String.duplicate("x", 100)}
        end

      assert {:error, {:data_too_large, size, 102_400}} =
               Validation.validate_memory_size(large_data)

      assert size > 102_400
    end
  end

  describe "validate_string_length/1" do
    test "returns :ok for strings within limit" do
      assert Validation.validate_string_length("hello") == :ok
    end

    test "returns :ok for empty string" do
      assert Validation.validate_string_length("") == :ok
    end

    test "returns :ok for string at limit" do
      string_10k = String.duplicate("x", 10_000)
      assert Validation.validate_string_length(string_10k) == :ok
    end

    test "returns error for string exceeding limit" do
      string_over_10k = String.duplicate("x", 10_001)

      assert {:error, {:string_too_long, 10_001, 10_000}} =
               Validation.validate_string_length(string_over_10k)
    end
  end

  describe "validate_importance/1" do
    test "returns :ok for valid importance scores" do
      assert Validation.validate_importance(0.0) == :ok
      assert Validation.validate_importance(0.5) == :ok
      assert Validation.validate_importance(1.0) == :ok
    end

    test "returns error for importance below 0" do
      assert Validation.validate_importance(-0.1) == {:error, {:invalid_importance, -0.1}}
    end

    test "returns error for importance above 1" do
      assert Validation.validate_importance(1.1) == {:error, {:invalid_importance, 1.1}}
    end

    test "returns error for non-float importance" do
      assert Validation.validate_importance(1) == {:error, {:invalid_importance, :not_a_float}}
      assert Validation.validate_importance(nil) == {:error, {:invalid_importance, :not_a_float}}

      assert Validation.validate_importance("0.5") ==
               {:error, {:invalid_importance, :not_a_float}}
    end
  end

  describe "validate_type/1" do
    test "returns :ok for all valid types" do
      valid_types = [
        :fact,
        :decision,
        :assumption,
        :analysis,
        :conversation,
        :file_context,
        :lesson_learned
      ]

      Enum.each(valid_types, fn type ->
        assert Validation.validate_type(type) == :ok
      end)
    end

    test "returns error for invalid type" do
      assert Validation.validate_type(:invalid_type) == {:error, {:invalid_type, :invalid_type}}
      assert Validation.validate_type(:random) == {:error, {:invalid_type, :random}}
    end
  end

  describe "validate_session_id/1" do
    test "returns :ok for valid session IDs" do
      assert Validation.validate_session_id("session_123") == :ok
      assert Validation.validate_session_id("abc") == :ok
      assert Validation.validate_session_id(String.duplicate("a", 256)) == :ok
    end

    test "returns error for empty string" do
      assert Validation.validate_session_id("") == {:error, :invalid_session_id}
    end

    test "returns error for non-binary" do
      assert Validation.validate_session_id(nil) == {:error, :invalid_session_id}
      assert Validation.validate_session_id(123) == {:error, :invalid_session_id}
      assert Validation.validate_session_id(:atom) == {:error, :invalid_session_id}
    end

    test "returns error for session ID exceeding max length" do
      long_id = String.duplicate("a", 257)

      assert {:error, {:session_id_too_long, 257, 256}} =
               Validation.validate_session_id(long_id)
    end
  end

  describe "validate_message/1" do
    test "returns :ok for valid message" do
      message = %{
        role: :user,
        content: "Hello, world!",
        timestamp: DateTime.utc_now()
      }

      assert Validation.validate_message(message) == :ok
    end

    test "returns :ok for message with minimal required fields" do
      message = %{role: :user, content: "test"}
      assert Validation.validate_message(message) == :ok
    end

    test "returns error when role is missing" do
      message = %{content: "test"}
      assert Validation.validate_message(message) == {:error, {:missing_field, :role}}
    end

    test "returns error when content is missing" do
      message = %{role: :user}
      assert Validation.validate_message(message) == {:error, {:missing_field, :content}}
    end

    test "returns error when content is too long" do
      long_content = String.duplicate("x", 10_001)
      message = %{role: :user, content: long_content}

      assert {:error, {:string_too_long, length, max}} = Validation.validate_message(message)
      assert length == 10_001
      assert max == 10_000
    end

    test "returns error for non-map message" do
      assert Validation.validate_message("not a map") == {:error, :invalid_message_format}
    end
  end

  describe "validate_memory/1" do
    test "returns {:ok, item} for valid memory" do
      item = %{
        id: "test_id",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.8,
        session_id: "session_123"
      }

      assert {:ok, ^item} = Validation.validate_memory(item)
    end

    test "returns :ok for all valid memory types" do
      valid_types = [
        :fact,
        :decision,
        :assumption,
        :analysis,
        :conversation,
        :file_context,
        :lesson_learned
      ]

      Enum.each(valid_types, fn type ->
        item = %{
          id: "id_#{type}",
          type: type,
          data: %{},
          importance: 0.5,
          session_id: "session_123"
        }

        assert {:ok, _} = Validation.validate_memory(item)
      end)
    end

    test "returns error when required fields are missing" do
      item = %{id: "test_id"}
      assert {:error, {:missing_fields, _}} = Validation.validate_memory(item)
    end

    test "returns error when data is too large" do
      large_data =
        for i <- 1..2000, into: %{} do
          {"key_#{i}", String.duplicate("x", 100)}
        end

      item = %{
        id: "test_id",
        type: :fact,
        data: large_data,
        importance: 0.5,
        session_id: "session_123"
      }

      assert {:error, {:data_too_large, _, _}} = Validation.validate_memory(item)
    end

    test "returns error when importance is invalid" do
      item = %{
        id: "test_id",
        type: :fact,
        data: %{},
        importance: 1.5,
        session_id: "session_123"
      }

      assert {:error, {:invalid_importance, 1.5}} = Validation.validate_memory(item)
    end

    test "returns error when type is invalid" do
      item = %{
        id: "test_id",
        type: :invalid_type,
        data: %{},
        importance: 0.5,
        session_id: "session_123"
      }

      assert {:error, {:invalid_type, :invalid_type}} = Validation.validate_memory(item)
    end

    test "returns error when session_id is invalid" do
      item = %{
        id: "test_id",
        type: :fact,
        data: %{},
        importance: 0.5,
        session_id: ""
      }

      assert {:error, :invalid_session_id} = Validation.validate_memory(item)
    end

    test "returns error for non-map input" do
      assert {:error, :not_a_map} = Validation.validate_memory("not a map")
    end
  end

  describe "validate_session_opts/1" do
    test "returns :ok for valid options" do
      opts = [max_messages: 100, max_tokens: 4000, max_context_items: 50]
      assert Validation.validate_session_opts(opts) == :ok
    end

    test "returns :ok for empty options" do
      assert Validation.validate_session_opts([]) == :ok
    end

    test "returns :ok for partial options" do
      assert Validation.validate_session_opts(max_messages: 50) == :ok
    end

    test "returns error when max_messages is invalid" do
      assert Validation.validate_session_opts(max_messages: -1) == {:error, :invalid_session_opts}

      assert Validation.validate_session_opts(max_messages: "100") ==
               {:error, :invalid_session_opts}
    end

    test "returns error when max_tokens is invalid" do
      assert Validation.validate_session_opts(max_tokens: 0) == {:error, :invalid_session_opts}
      assert Validation.validate_session_opts(max_tokens: nil) == {:error, :invalid_session_opts}
    end

    test "returns error when max_context_items is invalid" do
      assert Validation.validate_session_opts(max_context_items: -1) ==
               {:error, :invalid_session_opts}
    end

    test "returns error for non-list input" do
      assert Validation.validate_session_opts(%{max_messages: 100}) ==
               {:error, :invalid_session_opts}
    end
  end

  describe "ok?/1" do
    test "returns true for :ok" do
      assert Validation.ok?(:ok) == true
    end

    test "returns false for error tuple" do
      assert Validation.ok?({:error, :reason}) == false
    end

    test "returns false for other values" do
      assert Validation.ok?(nil) == false
      assert Validation.ok?(:other) == false
    end
  end

  describe "error?/1" do
    test "returns true for error tuple" do
      assert Validation.error?({:error, :reason}) == true
    end

    test "returns false for :ok" do
      assert Validation.error?(:ok) == false
    end

    test "returns false for other values" do
      assert Validation.error?(nil) == false
      assert Validation.error?(:other) == false
    end
  end

  describe "valid_types/0" do
    test "returns list of valid types" do
      types = Validation.valid_types()

      assert is_list(types)
      assert :fact in types
      assert :decision in types
      assert :analysis in types
      assert :conversation in types
      assert :file_context in types
      assert :lesson_learned in types
      assert :assumption in types
    end
  end

  describe "max_memory_size_bytes/0" do
    test "returns 100KB as max size" do
      assert Validation.max_memory_size_bytes() == 100 * 1024
    end
  end
end
