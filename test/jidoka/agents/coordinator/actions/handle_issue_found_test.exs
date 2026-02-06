defmodule Jidoka.Agents.Coordinator.Actions.HandleIssueFoundTest do
  use ExUnit.Case, async: true

  alias Jidoka.Agents.Coordinator.Actions.HandleIssueFound

  describe "run/2" do
    test "processes issue found and returns emit directive" do
      params = %{
        issue_type: "warning",
        message: "Unused variable 'x'",
        file_path: "/lib/test.ex",
        line: 42,
        column: 10,
        severity: :medium,
        session_id: "session-123"
      }

      context = %{
        agent_id: "coordinator-test",
        agent: %{state: %{active_tasks: %{}, event_aggregation: %{}}}
      }

      assert {:ok, result, directives} = HandleIssueFound.run(params, context)

      # Check result
      assert result.status == :broadcasted
      assert result.issue_type == "warning"
      assert result.severity == :medium

      # Action returns BOTH SetState and Emit directives
      assert length(directives) == 2

      # Find the SetState directive
      state_directive =
        Enum.find(directives, fn
          %Jido.Agent.StateOp.SetState{} -> true
          _ -> false
        end)

      assert state_directive != nil
      # Check that state was updated with issue aggregation
      assert state_directive.attrs.event_aggregation["issues_found"] != nil

      # Find the Emit directive
      emit_directive =
        Enum.find(directives, fn
          %Jido.Agent.Directive.Emit{} -> true
          _ -> false
        end)

      assert emit_directive != nil
      # BroadcastEvent signal structure: event_type + payload + optional session_id
      assert emit_directive.signal.data.event_type == "issue_found"
      assert emit_directive.signal.data.payload.message == "Unused variable 'x'"
      assert emit_directive.signal.data.payload.file_path == "/lib/test.ex"
      assert emit_directive.signal.data.payload.line == 42
      assert emit_directive.signal.data.payload.column == 10
      assert emit_directive.signal.data.session_id == "session-123"
    end

    test "uses default severity when not provided" do
      params = %{
        issue_type: "error",
        message: "Syntax error",
        file_path: "/lib/test.ex"
      }

      context = %{
        agent_id: "coordinator-test",
        agent: %{state: %{active_tasks: %{}, event_aggregation: %{}}}
      }

      assert {:ok, result, directives} = HandleIssueFound.run(params, context)

      assert result.status == :broadcasted

      # Find the Emit directive
      emit_directive =
        Enum.find(directives, fn
          %Jido.Agent.Directive.Emit{} -> true
          _ -> false
        end)

      assert emit_directive != nil
      # Severity is in payload
      assert emit_directive.signal.data.payload.severity == :medium
    end

    test "handles missing optional fields" do
      params = %{
        issue_type: "refactor",
        message: "Complex code",
        file_path: "/lib/complex.ex"
      }

      context = %{
        agent_id: "coordinator-test",
        agent: %{state: %{active_tasks: %{}, event_aggregation: %{}}}
      }

      assert {:ok, _result, directives} = HandleIssueFound.run(params, context)

      # Find the Emit directive
      emit_directive =
        Enum.find(directives, fn
          %Jido.Agent.Directive.Emit{} -> true
          _ -> false
        end)

      assert emit_directive != nil
      # Optional fields not present in payload
      refute Map.has_key?(emit_directive.signal.data.payload, :line)
      refute Map.has_key?(emit_directive.signal.data.payload, :column)
      # session_id not present at top level when not provided
      refute Map.has_key?(emit_directive.signal.data, :session_id)
    end
  end
end
