defmodule Jidoka.Agents.Coordinator.Actions.HandleIssueFound do
  @moduledoc """
  Action to handle issue found signals from analysis.

  This action processes `jido_coder.analysis.issue.found` signals
  and broadcasts them to connected clients.

  ## Signal Data

  * `:issue_type` - Type of issue (e.g., "warning", "error", "refactor")
  * `:message` - Issue description
  * `:file_path` - Path to the file where the issue was found
  * `:line` - Line number where the issue was found
  * `:severity` - Severity level (:low, :medium, :high, :critical)
  * `:session_id` - Optional associated session ID

  ## Directives

  Broadcasts to `jido.client.events` topic with the issue details.
  """

  use Jido.Action,
    name: "handle_issue_found",
    description: "Process code issue detection and broadcast to clients",
    category: "coordinator",
    tags: ["analysis", "issues", "broadcast"],
    vsn: "1.0.0",
    schema: [
      issue_type: [
        type: :string,
        required: true,
        doc: "Type of issue (warning, error, refactor, etc.)"
      ],
      message: [
        type: :string,
        required: true,
        doc: "Issue description"
      ],
      file_path: [
        type: :string,
        required: true,
        doc: "Path to the file with the issue"
      ],
      line: [
        type: :integer,
        required: false,
        doc: "Line number where issue was found"
      ],
      column: [
        type: :integer,
        required: false,
        doc: "Column number where issue was found"
      ],
      severity: [
        type: :atom,
        required: false,
        default: :medium,
        doc: "Severity level: :low, :medium, :high, :critical"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Session ID for targeted broadcasting"
      ]
    ]

  alias Jido.Agent.{Directive, StateOp}
  alias Jidoka.PubSub
  alias Jidoka.Signals

  alias Directive.Emit
  alias StateOp.SetState

  @impl true
  def run(params, context) do
    # Extract signal data
    issue_type = params[:issue_type]
    message = params[:message]
    file_path = params[:file_path]
    line = params[:line]
    column = params[:column]
    # Apply default severity if not provided
    severity = params[:severity] || :medium
    session_id = params[:session_id]

    # Build payload for client broadcast
    payload =
      %{
        issue_type: issue_type,
        message: message,
        file_path: file_path,
        severity: severity,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
      |> maybe_put_line(line)
      |> maybe_put_column(column)

    # Create client event signal with proper BroadcastEvent structure
    broadcast_params = %{
      event_type: "issue_found",
      payload: payload
    }

    broadcast_params =
      if session_id,
        do: Map.put(broadcast_params, :session_id, session_id),
        else: broadcast_params

    broadcast_signal = Signals.BroadcastEvent.new!(broadcast_params)

    # State updates: track issue in aggregation
    state_updates = %{
      event_aggregation: %{
        "issues_found" => %{
          count: increment_count(context, "issues_found"),
          last_issue: %{
            type: issue_type,
            severity: severity,
            file_path: file_path
          }
        }
      }
    }

    # Return result with state update and emit directive
    {:ok, %{status: :broadcasted, issue_type: issue_type, severity: severity},
     [
       %SetState{attrs: state_updates},
       %Emit{
         signal: broadcast_signal,
         dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
       }
     ]}
  end

  # Private helpers

  defp maybe_put_line(data, nil), do: data
  defp maybe_put_line(data, line), do: Map.put(data, :line, line)

  defp maybe_put_column(data, nil), do: data
  defp maybe_put_column(data, column), do: Map.put(data, :column, column)

  defp maybe_put_session_id(data, nil), do: data
  defp maybe_put_session_id(data, session_id), do: Map.put(data, :session_id, session_id)

  defp increment_count(context, key) do
    get_in(context[:agent_state] || %{}, [:event_aggregation, key, "count"]) ||
      0
      |> Kernel.+(1)
  end
end
