defmodule JidoCoderLib.Agent.StateTest do
  use ExUnit.Case, async: true

  alias JidoCoderLib.Agent.State

  describe "increment_field/3" do
    test "increments an integer field" do
      assert %{count: 6} == State.increment_field(%{count: 5}, :count)
    end

    test "increments by custom amount" do
      assert %{count: 7} == State.increment_field(%{count: 5}, :count, 2)
    end

    test "initializes missing field to 1" do
      assert %{count: 1} == State.increment_field(%{}, :count)
    end

    test "initializes missing field to custom amount" do
      assert %{count: 5} == State.increment_field(%{}, :count, 5)
    end

    test "increments nested field" do
      assert %{metrics: %{count: 6}} ==
               State.increment_field(%{metrics: %{count: 5}}, [:metrics, :count])
    end

    test "initializes missing nested field" do
      assert %{metrics: %{count: 1}} ==
               State.increment_field(%{metrics: %{}}, [:metrics, :count])
    end

    test "handles float fields" do
      assert %{count: 6.5} == State.increment_field(%{count: 5.5}, :count)
    end
  end

  describe "decrement_field/3" do
    test "decrements an integer field" do
      assert %{count: 4} == State.decrement_field(%{count: 5}, :count)
    end

    test "decrements by custom amount" do
      assert %{count: 2} == State.decrement_field(%{count: 5}, :count, 3)
    end
  end

  describe "put_nested/3" do
    test "puts value at nested path" do
      assert %{config: %{timeout: 5000}} == State.put_nested(%{}, [:config, :timeout], 5000)
    end

    test "creates intermediate maps" do
      assert %{level1: %{level2: %{level3: "value"}}} ==
               State.put_nested(%{}, [:level1, :level2, :level3], "value")
    end

    test "updates existing nested value" do
      assert %{config: %{timeout: 3000}} ==
               State.put_nested(%{config: %{timeout: 5000}}, [:config, :timeout], 3000)
    end
  end

  describe "get_nested/3" do
    test "gets value at nested path" do
      state = %{config: %{timeout: 5000}}
      assert 5000 == State.get_nested(state, [:config, :timeout])
    end

    test "returns nil for missing path" do
      assert nil == State.get_nested(%{}, [:config, :timeout])
    end

    test "returns custom default for missing path" do
      assert :default == State.get_nested(%{}, [:config, :timeout], :default)
    end
  end

  describe "update_timestamps/2" do
    test "updates single timestamp field" do
      result = State.update_timestamps(%{}, [:updated_at])

      assert Map.has_key?(result, :updated_at)
      assert result.updated_at =~ ~r/^\d{4}-\d{2}-\d{2}T/
    end

    test "updates multiple timestamp fields" do
      result = State.update_timestamps(%{}, [:created_at, :updated_at])

      assert Map.has_key?(result, :created_at)
      assert Map.has_key?(result, :updated_at)
    end

    test "updates nested timestamp field" do
      result = State.update_timestamps(%{metadata: %{}}, [[:metadata, :updated_at]])

      assert Map.has_key?(result.metadata, :updated_at)
    end
  end

  describe "add_task/3" do
    test "adds task to active_tasks" do
      result =
        State.add_task(%{}, "task_1", %{type: :analysis, status: :processing})

      assert %{"task_1" => %{type: :analysis, status: :processing}} =
               result.active_tasks
    end

    test "adds task to existing active_tasks" do
      state = %{active_tasks: %{"task_0" => %{}}}
      result = State.add_task(state, "task_1", %{})

      assert Map.has_key?(result.active_tasks, "task_0")
      assert Map.has_key?(result.active_tasks, "task_1")
    end
  end

  describe "update_task/3" do
    test "updates existing task" do
      state = %{active_tasks: %{"task_1" => %{status: :processing}}}
      result = State.update_task(state, "task_1", %{status: :completed})

      assert %{active_tasks: %{"task_1" => %{status: :completed}}} = result
    end

    test "merges updates with existing task info" do
      state = %{active_tasks: %{"task_1" => %{status: :processing, count: 5}}}
      result = State.update_task(state, "task_1", %{status: :completed})

      task = result.active_tasks["task_1"]
      assert task.status == :completed
      assert task.count == 5
    end

    test "returns unchanged state for non-existent task" do
      state = %{active_tasks: %{}}
      result = State.update_task(state, "task_1", %{status: :completed})

      assert state == result
    end
  end

  describe "remove_task/2" do
    test "removes task from active_tasks" do
      state = %{active_tasks: %{"task_1" => %{}}}
      result = State.remove_task(state, "task_1")

      assert %{} = result.active_tasks
    end

    test "handles empty active_tasks" do
      result = State.remove_task(%{}, "task_1")

      assert %{} = result.active_tasks
    end
  end

  describe "get_task/2" do
    test "returns task info" do
      state = %{active_tasks: %{"task_1" => %{status: :processing}}}

      assert %{status: :processing} == State.get_task(state, "task_1")
    end

    test "returns nil for non-existent task" do
      assert nil == State.get_task(%{}, "task_1")
    end
  end

  describe "has_task?/2" do
    test "returns true for existing task" do
      state = %{active_tasks: %{"task_1" => %{}}}

      assert State.has_task?(state, "task_1")
    end

    test "returns false for non-existent task" do
      refute State.has_task?(%{}, "task_1")
    end
  end

  describe "task_count/1" do
    test "returns count of active tasks" do
      state = %{
        active_tasks: %{
          "task_1" => %{},
          "task_2" => %{},
          "task_3" => %{}
        }
      }

      assert 3 == State.task_count(state)
    end

    test "returns zero for no active tasks" do
      assert 0 == State.task_count(%{})
      assert 0 == State.task_count(%{active_tasks: %{}})
    end
  end

  describe "increment_aggregation/3" do
    test "creates new aggregation entry" do
      result = State.increment_aggregation(%{}, "errors_found")

      assert result.event_aggregation["errors_found"][:count] == 1
    end

    test "increments existing aggregation" do
      state = %{event_aggregation: %{"errors_found" => %{count: 1}}}
      result = State.increment_aggregation(state, "errors_found")

      assert result.event_aggregation["errors_found"][:count] == 2
    end

    test "increments by custom amount" do
      result = State.increment_aggregation(%{}, "errors_found", 5)

      assert result.event_aggregation["errors_found"][:count] == 5
    end

    test "converts atom key to string" do
      result = State.increment_aggregation(%{}, :errors_found)

      assert result.event_aggregation["errors_found"][:count] == 1
    end
  end

  describe "update_aggregation_last/4" do
    test "sets last_* field in aggregation" do
      result = State.update_aggregation_last(%{}, "issues", :severity, :high)

      assert result.event_aggregation["issues"][:last_severity] == :high
    end

    test "preserves count when updating last field" do
      state = %{event_aggregation: %{"issues" => %{count: 5}}}
      result = State.update_aggregation_last(state, "issues", :severity, :high)

      assert result.event_aggregation["issues"][:count] == 5
      assert result.event_aggregation["issues"][:last_severity] == :high
    end
  end

  describe "get_aggregation/2" do
    test "returns aggregation entry" do
      state = %{event_aggregation: %{"errors" => %{count: 5}}}

      assert %{count: 5} == State.get_aggregation(state, "errors")
    end

    test "returns nil for non-existent aggregation" do
      assert nil == State.get_aggregation(%{}, "errors")
    end

    test "handles atom keys" do
      state = %{event_aggregation: %{"errors" => %{count: 5}}}

      assert %{count: 5} == State.get_aggregation(state, :errors)
    end
  end

  describe "merge/2" do
    test "merges updates into state" do
      result = State.merge(%{a: 1}, %{b: 2})

      assert %{a: 1, b: 2} == result
    end

    test "deep merges nested maps" do
      result = State.merge(%{config: %{timeout: 1000}}, %{config: %{retries: 3}})

      assert %{config: %{timeout: 1000, retries: 3}} == result
    end

    test "overwrites non-map values" do
      result = State.merge(%{config: %{timeout: 1000}}, %{config: %{timeout: 5000}})

      assert %{config: %{timeout: 5000}} == result
    end
  end
end
