defmodule Jidoka.Agents.Coordinator.Actions.HandleAnalysisCompleteTest do
  use ExUnit.Case, async: true

  alias Jidoka.Agents.Coordinator.Actions.HandleAnalysisComplete

  describe "run/2" do
    test "processes analysis complete and returns emit directive" do
      params = %{
        analysis_type: "credo",
        results: %{errors: 2, warnings: 5},
        session_id: "session-123",
        duration_ms: 150
      }

      context = %{
        agent_id: "coordinator-test",
        agent: %{state: %{active_tasks: %{}, event_aggregation: %{}}}
      }

      assert {:ok, result, directives} = HandleAnalysisComplete.run(params, context)

      # Check result
      assert result.status == :broadcasted
      assert result.analysis_type == "credo"

      # Action returns BOTH SetState and Emit directives
      assert length(directives) == 2

      # Find the SetState directive
      state_directive =
        Enum.find(directives, fn
          %Jido.Agent.StateOp.SetState{} -> true
          _ -> false
        end)

      assert state_directive != nil
      # event_aggregation uses string keys (from params)
      assert state_directive.attrs.event_aggregation["credo"] != nil
      assert state_directive.attrs.event_aggregation["credo"].results == %{errors: 2, warnings: 5}

      # Find the Emit directive
      emit_directive =
        Enum.find(directives, fn
          %Jido.Agent.Directive.Emit{} -> true
          _ -> false
        end)

      assert emit_directive != nil
      # BroadcastEvent signal structure: event_type + payload + optional session_id
      assert emit_directive.signal.data.event_type == "analysis_complete"
      assert emit_directive.signal.data.payload.analysis_type == "credo"
      assert emit_directive.signal.data.payload.results == %{errors: 2, warnings: 5}
      assert emit_directive.signal.data.payload.duration_ms == 150
      assert emit_directive.signal.data.session_id == "session-123"
    end

    test "handles missing optional fields" do
      params = %{
        analysis_type: "dialyzer",
        results: %{warnings: 3}
      }

      context = %{
        agent_id: "coordinator-test",
        agent: %{state: %{active_tasks: %{}, event_aggregation: %{}}}
      }

      assert {:ok, result, directives} = HandleAnalysisComplete.run(params, context)

      assert result.status == :broadcasted

      # Find the Emit directive
      emit_directive =
        Enum.find(directives, fn
          %Jido.Agent.Directive.Emit{} -> true
          _ -> false
        end)

      assert emit_directive != nil
      # session_id not present at top level when not provided
      refute Map.has_key?(emit_directive.signal.data, :session_id)
      # duration_ms not in payload when not provided
      refute Map.has_key?(emit_directive.signal.data.payload, :duration_ms)
    end
  end
end
