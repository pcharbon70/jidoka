defmodule Jidoka.Agents.Coordinator.Actions.HandleAnalysisComplete do
  @moduledoc """
  Action to handle analysis complete signals.

  This action processes `jido_coder.analysis.complete` signals,
  updates the coordinator's state, and broadcasts results to clients.

  ## Signal Data

  * `:analysis_type` - Type of analysis performed (e.g., "credo", "dialyzer")
  * `:results` - Analysis results map
  * `:session_id` - Optional associated session ID
  * `:duration_ms` - Optional analysis duration in milliseconds

  ## State Updates

  Adds the analysis to `event_aggregation` under the analysis_type key.

  ## Directives

  Broadcasts to `jido.client.events` topic with the analysis results.
  """

  use Jido.Action,
    name: "handle_analysis_complete",
    description: "Process analysis completion and broadcast to clients",
    category: "coordinator",
    tags: ["analysis", "broadcast"],
    vsn: "1.0.0",
    schema: [
      analysis_type: [
        type: :string,
        required: true,
        doc: "Type of analysis performed"
      ],
      results: [
        type: :map,
        required: true,
        doc: "Analysis results"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Session ID for targeted broadcasting"
      ],
      duration_ms: [
        type: :integer,
        required: false,
        doc: "Analysis duration in milliseconds"
      ]
    ]

  alias Jido.Agent.{Directive, StateOp}
  alias Jidoka.PubSub
  alias Jidoka.Signals

  alias Directive.Emit
  alias StateOp.SetState

  @impl true
  def run(params, _context) do
    # Extract signal data
    analysis_type = params[:analysis_type]
    results = params[:results]
    session_id = params[:session_id]
    duration_ms = params[:duration_ms]

    # Build payload for client broadcast
    payload =
      %{
        analysis_type: analysis_type,
        results: results,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
      |> maybe_put_duration(duration_ms)

    # Create client event signal with proper BroadcastEvent structure
    broadcast_params = %{
      event_type: "analysis_complete",
      payload: payload
    }

    broadcast_params =
      if session_id,
        do: Map.put(broadcast_params, :session_id, session_id),
        else: broadcast_params

    broadcast_signal = Signals.BroadcastEvent.new!(broadcast_params)

    # State updates: aggregate this analysis
    state_updates = %{
      event_aggregation: %{
        analysis_type => %{
          results: results,
          completed_at: DateTime.utc_now()
        }
      }
    }

    # Return result with state update and emit directive
    {:ok, %{status: :broadcasted, analysis_type: analysis_type},
     [
       %SetState{attrs: state_updates},
       %Emit{
         signal: broadcast_signal,
         dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
       }
     ]}
  end

  # Private helpers

  defp maybe_put_duration(data, nil), do: data
  defp maybe_put_duration(data, duration_ms), do: Map.put(data, :duration_ms, duration_ms)
end
