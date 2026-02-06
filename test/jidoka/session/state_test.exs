defmodule Jidoka.Session.StateTest do
  use ExUnit.Case, async: true

  alias Jidoka.Session.State

  @moduletag :session_state

  describe "new/2" do
    test "creates a new session state with default values" do
      session_id = "session-123"

      assert {:ok, state} = State.new(session_id)
      assert state.session_id == session_id
      assert state.status == :initializing
      assert state.config.max_conversations == 100
      assert state.config.timeout_minutes == 30
      assert state.config.persistence_enabled == false
      assert state.config.features == []
      assert state.llm_config == %{}
      assert state.metadata == %{}
      assert is_struct(state.created_at, DateTime)
      assert is_struct(state.updated_at, DateTime)
      assert state.active_tasks == []
      assert state.conversation_count == 0
      assert state.error == nil
    end

    test "creates a new session state with custom config" do
      session_id = "session-456"

      config = %State.Config{
        max_conversations: 50,
        timeout_minutes: 60,
        persistence_enabled: true,
        features: [:code_analysis, :file_editing]
      }

      llm_config = %{model: "gpt-4", temperature: 0.7}
      metadata = %{project: "my-project", user: "test-user"}

      assert {:ok, state} =
               State.new(session_id,
                 config: config,
                 llm_config: llm_config,
                 metadata: metadata
               )

      assert state.session_id == session_id
      assert state.config.max_conversations == 50
      assert state.config.timeout_minutes == 60
      assert state.config.persistence_enabled == true
      assert state.config.features == [:code_analysis, :file_editing]
      assert state.llm_config == llm_config
      assert state.metadata == metadata
    end

    test "rejects invalid session_id (non-binary)" do
      assert {:error, :invalid_session_id} = State.new(123)
      assert {:error, :invalid_session_id} = State.new(nil)
      assert {:error, :invalid_session_id} = State.new(:atom)
    end

    test "rejects empty string session_id" do
      assert {:error, {:empty_field, "session_id"}} = State.new("")
    end

    test "sets status to :initializing by default" do
      assert {:ok, state} = State.new("session-xyz")
      assert state.status == :initializing
    end

    test "created_at and updated_at are set to current time" do
      before = DateTime.utc_now()
      assert {:ok, state} = State.new("session-time")
      after_time = DateTime.utc_now()

      assert DateTime.compare(state.created_at, before) in [:gt, :eq]
      assert DateTime.compare(state.created_at, after_time) in [:lt, :eq]
      assert DateTime.compare(state.updated_at, before) in [:gt, :eq]
      assert DateTime.compare(state.updated_at, after_time) in [:lt, :eq]
    end
  end

  describe "Config struct" do
    test "creates default config" do
      config = struct(State.Config)

      assert config.max_conversations == 100
      assert config.timeout_minutes == 30
      assert config.persistence_enabled == false
      assert config.features == []
    end

    test "creates custom config" do
      config = %State.Config{
        max_conversations: 200,
        timeout_minutes: 90,
        persistence_enabled: true,
        features: [:feature1, :feature2]
      }

      assert config.max_conversations == 200
      assert config.timeout_minutes == 90
      assert config.persistence_enabled == true
      assert config.features == [:feature1, :feature2]
    end
  end

  describe "transition/2" do
    setup do
      {:ok, state} = State.new("session-transition")
      %{state: state}
    end

    test "allows transition from :initializing to :active", %{state: state} do
      assert {:ok, new_state} = State.transition(state, :active)
      assert new_state.status == :active
      assert DateTime.after?(new_state.updated_at, state.updated_at)
    end

    test "allows transition from :initializing to :terminated", %{state: state} do
      assert {:ok, new_state} = State.transition(state, :terminated)
      assert new_state.status == :terminated
    end

    test "allows transition from :active to :idle", %{state: state} do
      assert {:ok, active_state} = State.transition(state, :active)
      assert {:ok, idle_state} = State.transition(active_state, :idle)
      assert idle_state.status == :idle
    end

    test "allows transition from :idle to :active", %{state: state} do
      assert {:ok, active_state} = State.transition(state, :active)
      assert {:ok, idle_state} = State.transition(active_state, :idle)
      assert {:ok, new_active_state} = State.transition(idle_state, :active)
      assert new_active_state.status == :active
    end

    test "allows transition from :active to :terminating", %{state: state} do
      assert {:ok, active_state} = State.transition(state, :active)
      assert {:ok, terminating_state} = State.transition(active_state, :terminating)
      assert terminating_state.status == :terminating
    end

    test "allows transition from :idle to :terminating", %{state: state} do
      assert {:ok, active_state} = State.transition(state, :active)
      assert {:ok, idle_state} = State.transition(active_state, :idle)
      assert {:ok, terminating_state} = State.transition(idle_state, :terminating)
      assert terminating_state.status == :terminating
    end

    test "allows transition from :terminating to :terminated", %{state: state} do
      assert {:ok, active_state} = State.transition(state, :active)
      assert {:ok, terminating_state} = State.transition(active_state, :terminating)
      assert {:ok, terminated_state} = State.transition(terminating_state, :terminated)
      assert terminated_state.status == :terminated
    end

    test "rejects transition from :active to :initializing", %{state: state} do
      assert {:ok, active_state} = State.transition(state, :active)
      assert {:error, :invalid_transition} = State.transition(active_state, :initializing)
    end

    test "rejects transition from :active to :terminated (must go through :terminating)", %{
      state: state
    } do
      assert {:ok, active_state} = State.transition(state, :active)
      assert {:error, :invalid_transition} = State.transition(active_state, :terminated)
    end

    test "rejects transition from :terminated (terminal state)", %{state: state} do
      assert {:ok, active_state} = State.transition(state, :active)
      assert {:ok, terminating_state} = State.transition(active_state, :terminating)
      assert {:ok, terminated_state} = State.transition(terminating_state, :terminated)

      # Cannot transition from :terminated
      assert {:error, :invalid_transition} = State.transition(terminated_state, :active)
      assert {:error, :invalid_transition} = State.transition(terminated_state, :initializing)
    end

    test "rejects transition from :initializing to :idle", %{state: state} do
      assert {:error, :invalid_transition} = State.transition(state, :idle)
    end

    test "rejects invalid status atom", %{state: state} do
      assert {:error, :invalid_transition} = State.transition(state, :invalid_status)
      assert {:error, :invalid_transition} = State.transition(state, :random)
    end

    test "updates updated_at timestamp on transition", %{state: state} do
      # Ensure time difference
      Process.sleep(10)
      assert {:ok, new_state} = State.transition(state, :active)
      assert DateTime.after?(new_state.updated_at, state.updated_at)
    end
  end

  describe "valid_transition?/2" do
    test "returns true for valid transitions" do
      assert State.valid_transition?(:initializing, :active) == true
      assert State.valid_transition?(:initializing, :terminated) == true
      assert State.valid_transition?(:active, :idle) == true
      assert State.valid_transition?(:active, :terminating) == true
      assert State.valid_transition?(:idle, :active) == true
      assert State.valid_transition?(:idle, :terminating) == true
      assert State.valid_transition?(:terminating, :terminated) == true
    end

    test "returns false for invalid transitions" do
      assert State.valid_transition?(:active, :initializing) == false
      assert State.valid_transition?(:active, :terminated) == false
      assert State.valid_transition?(:idle, :initializing) == false
      assert State.valid_transition?(:terminated, :active) == false
      assert State.valid_transition?(:terminated, :initializing) == false
      assert State.valid_transition?(:initializing, :idle) == false
    end

    test "returns false for terminal state :terminated" do
      assert State.valid_transition?(:terminated, :active) == false
      assert State.valid_transition?(:terminated, :idle) == false
      assert State.valid_transition?(:terminated, :terminating) == false
      assert State.valid_transition?(:terminated, :initializing) == false
      assert State.valid_transition?(:terminated, :terminated) == false
    end

    test "returns false for unknown statuses" do
      assert State.valid_transition?(:unknown, :active) == false
      assert State.valid_transition?(:initializing, :unknown) == false
    end
  end

  describe "update/2" do
    setup do
      {:ok, state} = State.new("session-update")
      %{state: state}
    end

    test "updates conversation_count", %{state: state} do
      assert {:ok, updated} = State.update(state, %{conversation_count: 5})
      assert updated.conversation_count == 5
      assert updated.session_id == state.session_id
      assert updated.status == state.status
    end

    test "updates active_tasks", %{state: state} do
      assert {:ok, updated} = State.update(state, %{active_tasks: ["task-1", "task-2"]})
      assert updated.active_tasks == ["task-1", "task-2"]
    end

    test "updates error field", %{state: state} do
      assert {:ok, updated} = State.update(state, %{error: "Something went wrong"})
      assert updated.error == "Something went wrong"
    end

    test "updates llm_config", %{state: state} do
      new_llm_config = %{model: "gpt-4", temperature: 0.8}
      assert {:ok, updated} = State.update(state, %{llm_config: new_llm_config})
      assert updated.llm_config == new_llm_config
    end

    test "updates metadata", %{state: state} do
      new_metadata = %{project: "updated-project"}
      assert {:ok, updated} = State.update(state, %{metadata: new_metadata})
      assert updated.metadata == new_metadata
    end

    test "updates multiple fields at once", %{state: state} do
      assert {:ok, updated} =
               State.update(state, %{
                 conversation_count: 10,
                 active_tasks: ["task-1"],
                 error: "error message"
               })

      assert updated.conversation_count == 10
      assert updated.active_tasks == ["task-1"]
      assert updated.error == "error message"
    end

    test "automatically updates updated_at timestamp", %{state: state} do
      Process.sleep(10)
      assert {:ok, updated} = State.update(state, %{conversation_count: 1})
      assert DateTime.after?(updated.updated_at, state.updated_at)
    end

    test "rejects invalid session_id update", %{state: state} do
      assert {:error, :invalid_session_id} = State.update(state, %{session_id: 123})
    end

    test "rejects invalid status update", %{state: state} do
      assert {:error, :invalid_status} = State.update(state, %{status: :invalid})
    end

    test "rejects invalid conversation_count", %{state: state} do
      assert {:error, :invalid_counts} = State.update(state, %{conversation_count: -1})
    end

    test "rejects invalid active_tasks", %{state: state} do
      assert {:error, :invalid_counts} = State.update(state, %{active_tasks: "not-a-list"})
    end
  end

  describe "valid?/1" do
    test "returns :ok for valid state" do
      assert {:ok, state} = State.new("session-valid")
      assert :ok = State.valid?(state)
    end

    test "returns error for state with invalid session_id" do
      invalid_state = %State{session_id: 123, status: :initializing}
      assert {:error, :invalid_session_id} = State.valid?(invalid_state)
    end

    test "returns error for state with invalid status" do
      valid_state = struct(State, session_id: "valid", status: :initializing)
      invalid_state = %{valid_state | status: :invalid}
      assert {:error, :invalid_status} = State.valid?(invalid_state)
    end

    test "returns error for state with invalid timestamps" do
      invalid_state = %State{
        session_id: "valid",
        status: :initializing,
        created_at: "not-a-datetime",
        updated_at: "not-a-datetime"
      }

      assert {:error, :invalid_timestamps} = State.valid?(invalid_state)
    end

    test "returns error for state with invalid counts" do
      invalid_state = %State{
        session_id: "valid",
        status: :initializing,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        conversation_count: -1
      }

      assert {:error, :invalid_counts} = State.valid?(invalid_state)
    end
  end

  describe "serialize/1" do
    setup do
      config = %State.Config{
        max_conversations: 50,
        timeout_minutes: 60,
        persistence_enabled: true,
        features: [:code_analysis, :file_editing]
      }

      {:ok, state} =
        State.new("session-serialize",
          config: config,
          llm_config: %{model: "gpt-4"},
          metadata: %{project: "test"}
        )

      %{state: state}
    end

    test "serializes state to map with string keys", %{state: state} do
      serialized = State.serialize(state)

      assert is_map(serialized)
      assert Map.has_key?(serialized, "session_id")
      assert Map.has_key?(serialized, "status")
      assert Map.has_key?(serialized, "config")
      assert Map.has_key?(serialized, "llm_config")
      assert Map.has_key?(serialized, "metadata")
      assert Map.has_key?(serialized, "created_at")
      assert Map.has_key?(serialized, "updated_at")
    end

    test "serializes session_id as string", %{state: state} do
      serialized = State.serialize(state)
      assert serialized["session_id"] == "session-serialize"
    end

    test "serializes status as string", %{state: state} do
      serialized = State.serialize(state)
      assert serialized["status"] == "initializing"
    end

    test "serializes config as map with string keys", %{state: state} do
      serialized = State.serialize(state)
      config = serialized["config"]

      assert config["max_conversations"] == 50
      assert config["timeout_minutes"] == 60
      assert config["persistence_enabled"] == true
      assert config["features"] == ["code_analysis", "file_editing"]
    end

    test "serializes llm_config as map", %{state: state} do
      serialized = State.serialize(state)
      assert serialized["llm_config"] == %{model: "gpt-4"}
    end

    test "serializes metadata as map", %{state: state} do
      serialized = State.serialize(state)
      assert serialized["metadata"] == %{project: "test"}
    end

    test "serializes timestamps as ISO8601 strings", %{state: state} do
      serialized = State.serialize(state)

      assert is_binary(serialized["created_at"])
      assert is_binary(serialized["updated_at"])

      # Verify valid ISO8601 format
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(serialized["created_at"])
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(serialized["updated_at"])
    end

    test "serializes active_tasks and conversation_count", %{state: state} do
      updated_state = %{state | active_tasks: ["task-1"], conversation_count: 5}
      serialized = State.serialize(updated_state)

      assert serialized["active_tasks"] == ["task-1"]
      assert serialized["conversation_count"] == 5
    end

    test "handles nil values in serialization", %{state: state} do
      state_with_error = %{state | error: "error message"}
      serialized = State.serialize(state_with_error)

      assert serialized["error"] == "error message"
    end
  end

  describe "deserialize/1" do
    setup do
      config = %State.Config{
        max_conversations: 50,
        timeout_minutes: 60,
        persistence_enabled: true,
        features: [:code_analysis, :file_editing]
      }

      {:ok, state} =
        State.new("session-deserialize",
          config: config,
          llm_config: %{model: "gpt-4"},
          metadata: %{project: "test"}
        )

      %{serialized: State.serialize(state), original: state}
    end

    test "deserializes valid map to State struct", %{serialized: serialized} do
      assert {:ok, deserialized} = State.deserialize(serialized)
      assert is_struct(deserialized, State)
    end

    test "deserializes session_id correctly", %{serialized: serialized} do
      assert {:ok, deserialized} = State.deserialize(serialized)
      assert deserialized.session_id == "session-deserialize"
    end

    test "deserializes status correctly", %{serialized: serialized} do
      assert {:ok, deserialized} = State.deserialize(serialized)
      assert deserialized.status == :initializing
    end

    test "deserializes config correctly", %{serialized: serialized} do
      assert {:ok, deserialized} = State.deserialize(serialized)

      assert deserialized.config.max_conversations == 50
      assert deserialized.config.timeout_minutes == 60
      assert deserialized.config.persistence_enabled == true
      assert deserialized.config.features == [:code_analysis, :file_editing]
    end

    test "deserializes llm_config correctly", %{serialized: serialized} do
      assert {:ok, deserialized} = State.deserialize(serialized)
      assert deserialized.llm_config == %{model: "gpt-4"}
    end

    test "deserializes metadata correctly", %{serialized: serialized} do
      assert {:ok, deserialized} = State.deserialize(serialized)
      assert deserialized.metadata == %{project: "test"}
    end

    test "deserializes timestamps correctly", %{serialized: serialized} do
      assert {:ok, deserialized} = State.deserialize(serialized)
      assert is_struct(deserialized.created_at, DateTime)
      assert is_struct(deserialized.updated_at, DateTime)
    end

    test "deserializes active_tasks and conversation_count", %{serialized: serialized} do
      # Create a new map with the values we want to test
      modified =
        Map.merge(serialized, %{
          "active_tasks" => ["task-1"],
          "conversation_count" => 5
        })

      assert {:ok, deserialized} = State.deserialize(modified)
      assert deserialized.active_tasks == ["task-1"]
      assert deserialized.conversation_count == 5
    end

    test "returns error for missing session_id" do
      invalid_map = %{"status" => "active"}
      assert {:error, {:missing_field, "session_id"}} = State.deserialize(invalid_map)
    end

    test "returns error for empty session_id" do
      invalid_map = %{
        "session_id" => "",
        "status" => "active",
        "created_at" => "2025-01-23T00:00:00Z",
        "updated_at" => "2025-01-23T00:00:00Z"
      }

      assert {:error, {:empty_field, "session_id"}} = State.deserialize(invalid_map)
    end

    test "returns error for missing status" do
      invalid_map = %{"session_id" => "test"}
      assert {:error, {:missing_field, "status"}} = State.deserialize(invalid_map)
    end

    test "returns error for missing datetime fields" do
      invalid_map = %{
        "session_id" => "test",
        "status" => "active"
      }

      assert {:error, :missing_datetime} = State.deserialize(invalid_map)
    end

    test "round-trip: serialize then deserialize produces equivalent state", %{
      serialized: serialized,
      original: original
    } do
      assert {:ok, deserialized} = State.deserialize(serialized)

      assert deserialized.session_id == original.session_id
      assert deserialized.status == original.status
      assert deserialized.config.max_conversations == original.config.max_conversations
      assert deserialized.config.timeout_minutes == original.config.timeout_minutes
      assert deserialized.config.persistence_enabled == original.config.persistence_enabled
      assert deserialized.config.features == original.config.features
      assert deserialized.llm_config == original.llm_config
      assert deserialized.metadata == original.metadata
    end
  end

  describe "integration tests" do
    test "complete session lifecycle" do
      # Create session
      assert {:ok, session} = State.new("lifecycle-session")

      # Transition to active
      assert {:ok, session} = State.transition(session, :active)
      assert session.status == :active

      # Update with activity
      assert {:ok, session} =
               State.update(session, %{
                 conversation_count: 5,
                 active_tasks: ["task-1", "task-2"]
               })

      # Transition to idle
      assert {:ok, session} = State.transition(session, :idle)
      assert session.status == :idle

      # Back to active
      assert {:ok, session} = State.transition(session, :active)
      assert session.status == :active

      # Transition to terminating
      assert {:ok, session} = State.transition(session, :terminating)
      assert session.status == :terminating

      # Finally terminate
      assert {:ok, session} = State.transition(session, :terminated)
      assert session.status == :terminated

      # Cannot transition from terminated
      assert {:error, :invalid_transition} = State.transition(session, :active)
    end

    test "serialize and deserialize session through lifecycle" do
      # Create and setup session
      assert {:ok, original} =
               State.new("lifecycle-serialize",
                 config: %State.Config{max_conversations: 100},
                 llm_config: %{model: "gpt-4"},
                 metadata: %{project: "test"}
               )

      assert {:ok, original} = State.transition(original, :active)
      assert {:ok, original} = State.update(original, %{conversation_count: 10})

      # Serialize
      serialized = State.serialize(original)

      # Deserialize
      assert {:ok, restored} = State.deserialize(serialized)

      # Verify all fields
      assert restored.session_id == original.session_id
      assert restored.status == original.status
      assert restored.conversation_count == original.conversation_count
      assert restored.config.max_conversations == original.config.max_conversations
      assert restored.llm_config == original.llm_config
      assert restored.metadata == original.metadata
    end
  end
end
