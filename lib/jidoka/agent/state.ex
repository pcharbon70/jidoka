defmodule Jidoka.Agent.State do
  @moduledoc """
  State management utilities for Jidoka agents.

  This module provides helper functions for common state operations
  in agent actions. These utilities complement Jido's StateOp.SetState
  with convenient functions for common patterns.

  ## Numeric Operations

  Increment or decrement numeric fields:

      # Increment a counter
      new_state = State.increment_field(state, :count)

      # Increment by custom amount
      new_state = State.increment_field(state, :count, 5)

      # Decrement
      new_state = State.increment_field(state, :count, -1)

  ## Nested State Updates

  Update nested map structures safely:

      new_state = State.put_nested(state, [:config, :timeout], 5000)

  ## Timestamp Updates

  Update timestamp fields to current time:

      new_state = State.update_timestamps(state, [:started_at, :updated_at])

  ## Task Management

  Common task state operations:

      # Add active task
      new_state = State.add_task(state, "task_1", %{type: :analysis, status: :processing})

      # Update task
      new_state = State.update_task(state, "task_1", %{status: :completed})

      # Remove task
      new_state = State.remove_task(state, "task_1")

  ## Aggregation

  Update aggregated counters:

      new_state = State.increment_aggregation(state, "errors_found")
      new_state = State.increment_aggregation(state, "errors_found", 5)

  """

  @type agent_state :: map()
  @type task_id :: String.t()
  @type task_info :: map()

  @doc """
  Safely increments a numeric state field.

  If the field doesn't exist or isn't numeric, initializes it to the
  increment value (default 1).

  ## Parameters

  * `state` - The agent state map
  * `field` - The field to increment (atom or list of atoms for nested path)
  * `amount` - The amount to increment (default: 1)

  ## Examples

      iex> State.increment_field(%{count: 5}, :count)
      %{count: 6}

      iex> State.increment_field(%{count: 5}, :count, 2)
      %{count: 7}

      iex> State.increment_field(%{}, :count)
      %{count: 1}

      iex> State.increment_field(%{metrics: %{count: 5}}, [:metrics, :count])
      %{metrics: %{count: 6}}

  """
  @spec increment_field(agent_state(), atom() | [atom()], integer()) :: agent_state()
  def increment_field(state, field, amount \\ 1)

  def increment_field(state, field, amount) when is_atom(field) do
    current = Map.get(state, field, 0)

    value =
      cond do
        is_integer(current) -> current + amount
        is_float(current) -> current + amount
        true -> amount
      end

    Map.put(state, field, value)
  end

  def increment_field(state, [head | tail] = path, amount) when is_atom(head) do
    current = get_in(state, path)

    value =
      cond do
        is_integer(current) -> current + amount
        is_float(current) -> current + amount
        true -> amount
      end

    put_in(state, path, value)
  end

  @doc """
  Decrements a numeric state field.

  This is equivalent to `increment_field(state, field, -1)`.

  ## Examples

      iex> State.decrement_field(%{count: 5}, :count)
      %{count: 4}

  """
  @spec decrement_field(agent_state(), atom() | [atom()], integer()) :: agent_state()
  def decrement_field(state, field, amount \\ 1) do
    increment_field(state, field, -amount)
  end

  @doc """
  Puts a value at a nested path in the state map.

  Creates intermediate maps as needed if the path doesn't exist.

  ## Parameters

  * `state` - The agent state map
  * `path` - List of atoms representing the nested path
  * `value` - The value to set

  ## Examples

      iex> State.put_nested(%{}, [:config, :timeout], 5000)
      %{config: %{timeout: 5000}}

      iex> State.put_nested(%{config: %{}}, [:config, :timeout], 5000)
      %{config: %{timeout: 5000}}

  """
  @spec put_nested(agent_state(), [atom()], term()) :: agent_state()
  def put_nested(state, [head | tail] = _path, value) when is_atom(head) do
    update_in(state, [Access.key(head, %{})], &do_put_nested(&1, tail, value))
  end

  defp do_put_nested(current, [], value), do: value

  defp do_put_nested(current, [head | tail], value) do
    update_in(current, [Access.key(head, %{})], &do_put_nested(&1, tail, value))
  end

  @doc """
  Gets a value at a nested path in the state map.

  Returns `default` (nil) if the path doesn't exist.

  ## Examples

      iex> State.get_nested(%{config: %{timeout: 5000}}, [:config, :timeout])
      5000

      iex> State.get_nested(%{config: %{}}, [:config, :timeout])
      nil

  """
  @spec get_nested(agent_state(), [atom()], term()) :: term()
  def get_nested(state, [head | tail] = _path, default \\ nil) do
    get_in(state, [head | tail]) || default
  end

  @doc """
  Updates timestamp fields to current UTC time.

  ## Parameters

  * `state` - The agent state map
  * `fields` - List of field names to update (atoms or paths)

  ## Examples

      iex> State.update_timestamps(%{}, [:updated_at])
      %{updated_at: "2025-01-23T12:00:00.000000Z"}

      iex> State.update_timestamps(%{data: %{}}, [[:data, :updated_at]])
      %{data: %{updated_at: "2025-01-23T12:00:00.000000Z"}}

  """
  @spec update_timestamps(agent_state(), [atom() | [atom()]]) :: agent_state()
  def update_timestamps(state, fields) when is_list(fields) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    Enum.reduce(fields, state, fn field, acc ->
      put_timestamp(acc, field, timestamp)
    end)
  end

  defp put_timestamp(state, field, timestamp) when is_atom(field) do
    Map.put(state, field, timestamp)
  end

  defp put_timestamp(state, [head | []] = _path, timestamp) do
    # Last element in path - set the value directly
    Map.put(state, head, timestamp)
  end

  defp put_timestamp(state, [head | tail] = _path, timestamp) do
    nested = Map.get(state, head, %{})
    updated = put_timestamp(nested, tail, timestamp)
    Map.put(state, head, updated)
  end

  @doc """
  Adds a task to the active_tasks map.

  ## Parameters

  * `state` - The agent state map
  * `task_id` - Unique identifier for the task
  * `task_info` - Map containing task information

  ## Examples

      iex> State.add_task(%{}, "task_1", %{type: :analysis, status: :processing})
      %{active_tasks: %{"task_1" => %{type: :analysis, status: :processing}}}

  """
  @spec add_task(agent_state(), task_id(), task_info()) :: agent_state()
  def add_task(state, task_id, task_info) when is_map(task_info) do
    tasks = Map.get(state, :active_tasks, %{})
    updated_tasks = Map.put(tasks, task_id, task_info)
    Map.put(state, :active_tasks, updated_tasks)
  end

  @doc """
  Updates a task in the active_tasks map.

  If the task doesn't exist, does nothing.

  ## Parameters

  * `state` - The agent state map
  * `task_id` - Unique identifier for the task
  * `updates` - Map containing fields to update

  ## Examples

      iex> state = %{active_tasks: %{"task_1" => %{status: :processing}}}
      iex> State.update_task(state, "task_1", %{status: :completed})
      %{active_tasks: %{"task_1" => %{status: :completed}}}

  """
  @spec update_task(agent_state(), task_id(), map()) :: agent_state()
  def update_task(state, task_id, updates) when is_map(updates) do
    tasks = Map.get(state, :active_tasks, %{})

    case Map.get(tasks, task_id) do
      nil ->
        state

      task_info ->
        updated_task = Map.merge(task_info, updates)
        updated_tasks = Map.put(tasks, task_id, updated_task)
        Map.put(state, :active_tasks, updated_tasks)
    end
  end

  @doc """
  Removes a task from the active_tasks map.

  ## Parameters

  * `state` - The agent state map
  * `task_id` - Unique identifier for the task

  ## Examples

      iex> state = %{active_tasks: %{"task_1" => %{status: :completed}}}
      iex> State.remove_task(state, "task_1")
      %{active_tasks: %{}}

  """
  @spec remove_task(agent_state(), task_id()) :: agent_state()
  def remove_task(state, task_id) do
    tasks = Map.get(state, :active_tasks, %{})
    updated_tasks = Map.delete(tasks, task_id)
    Map.put(state, :active_tasks, updated_tasks)
  end

  @doc """
  Gets a task from the active_tasks map.

  Returns `nil` if the task doesn't exist.

  ## Examples

      iex> state = %{active_tasks: %{"task_1" => %{status: :processing}}}
      iex> State.get_task(state, "task_1")
      %{status: :processing}

  """
  @spec get_task(agent_state(), task_id()) :: task_info() | nil
  def get_task(state, task_id) do
    tasks = Map.get(state, :active_tasks, %{})
    Map.get(tasks, task_id)
  end

  @doc """
  Checks if a task exists in the active_tasks map.

  ## Examples

      iex> state = %{active_tasks: %{"task_1" => %{status: :processing}}}
      iex> State.has_task?(state, "task_1")
      true

      iex> State.has_task?(state, "task_2")
      false

  """
  @spec has_task?(agent_state(), task_id()) :: boolean()
  def has_task?(state, task_id) do
    tasks = Map.get(state, :active_tasks, %{})
    Map.has_key?(tasks, task_id)
  end

  @doc """
  Returns the count of active tasks.

  ## Examples

      iex> state = %{active_tasks: %{"task_1" => {}, "task_2" => {}}}
      iex> State.task_count(state)
      2

  """
  @spec task_count(agent_state()) :: non_neg_integer()
  def task_count(state) do
    tasks = Map.get(state, :active_tasks, %{})
    map_size(tasks)
  end

  @doc """
  Increments an aggregation counter.

  Aggregation counters are stored under the `:event_aggregation` key.

  ## Parameters

  * `state` - The agent state map
  * `key` - The aggregation key (can be a string or atom)
  * `amount` - The amount to increment (default: 1)

  ## Examples

      iex> State.increment_aggregation(%{}, "errors_found")
      %{event_aggregation: %{"errors_found" => %{count: 1}}}

      iex> state = %{event_aggregation: %{"errors_found" => %{count: 1}}}
      iex> State.increment_aggregation(state, "errors_found", 2)
      %{event_aggregation: %{"errors_found" => %{count: 3}}}

  """
  @spec increment_aggregation(agent_state(), String.t() | atom(), integer()) :: agent_state()
  def increment_aggregation(state, key, amount \\ 1) do
    key_str = to_string(key)
    aggregation = Map.get(state, :event_aggregation, %{})

    current_entry = Map.get(aggregation, key_str, %{})
    current_count = Map.get(current_entry, :count, 0)

    updated_entry = Map.put(current_entry, :count, current_count + amount)
    updated_aggregation = Map.put(aggregation, key_str, updated_entry)

    Map.put(state, :event_aggregation, updated_aggregation)
  end

  @doc """
  Updates the last_* field in an aggregation entry.

  ## Parameters

  * `state` - The agent state map
  * `key` - The aggregation key
  * `field_name` - The name of the last_* field to set
  * `value` - The value to set

  ## Examples

      iex> State.update_aggregation_last(%{}, "issues", :severity, :high)
      %{event_aggregation: %{"issues" => %{count: 0, last_severity: :high}}}

  """
  @spec update_aggregation_last(agent_state(), String.t() | atom(), atom(), term()) ::
          agent_state()
  def update_aggregation_last(state, key, field_name, value) do
    key_str = to_string(key)
    field_name_str = :"last_#{field_name}"
    aggregation = Map.get(state, :event_aggregation, %{})

    current_entry = Map.get(aggregation, key_str, %{count: 0})
    updated_entry = Map.put(current_entry, field_name_str, value)
    updated_aggregation = Map.put(aggregation, key_str, updated_entry)

    Map.put(state, :event_aggregation, updated_aggregation)
  end

  @doc """
  Gets an aggregation entry by key.

  Returns `nil` if the aggregation doesn't exist.

  ## Examples

      iex> state = %{event_aggregation: %{"errors" => %{count: 5}}}
      iex> State.get_aggregation(state, "errors")
      %{count: 5}

  """
  @spec get_aggregation(agent_state(), String.t() | atom()) :: map() | nil
  def get_aggregation(state, key) do
    key_str = to_string(key)
    aggregation = Map.get(state, :event_aggregation, %{})
    Map.get(aggregation, key_str)
  end

  @doc """
  Merges updates into the agent state.

  This is a deep merge that preserves nested structures.

  ## Parameters

  * `state` - The agent state map
  * `updates` - Map containing updates to merge

  ## Examples

      iex> State.merge(%{config: %{timeout: 1000}}, %{config: %{retries: 3}})
      %{config: %{timeout: 1000, retries: 3}}

  """
  @spec merge(agent_state(), map()) :: agent_state()
  def merge(state, updates) when is_map(updates) do
    deep_merge(state, updates)
  end

  # Private helper for deep merge
  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _k, v1, v2 ->
      if is_map(v1) and is_map(v2) do
        deep_merge(v1, v2)
      else
        v2
      end
    end)
  end
end
