defmodule Jidoka.Signals.AnalysisComplete do
  @moduledoc """
  Signal emitted when code analysis completes.

  This signal follows the CloudEvents v1.0.2 specification and is used
  to broadcast results from code analysis operations (e.g., Credo, dialyzer,
  custom type checking).

  ## Fields

  - `:analysis_type` - Type of analysis performed (e.g., "credo", "dialyzer", "type_check") (required)
  - `:results` - Analysis results map (required)
  - `:session_id` - Optional associated session ID
  - `:duration_ms` - Optional analysis duration in milliseconds

  ## Examples

      iex> {:ok, signal} = Jidoka.Signals.AnalysisComplete.new(%{
      ...>   analysis_type: "credo",
      ...>   results: %{errors: [], warnings: ["unused var"]}
      ...> })
      iex> signal.type
      "jido_coder.analysis.complete"

      iex> {:ok, signal} = Jidoka.Signals.AnalysisComplete.new(%{
      ...>   analysis_type: "dialyzer",
      ...>   results: %{warnings: 5},
      ...>   session_id: "session-123",
      ...>   duration_ms: 150
      ...> })

  """

  use Jido.Signal,
    type: "jido_coder.analysis.complete",
    default_source: "/jido_coder/analyzer",
    schema: [
      analysis_type: [
        type: :string,
        required: true,
        doc: "Type of analysis performed (e.g., credo, dialyzer, type_check)"
      ],
      results: [
        type: :map,
        required: true,
        doc: "Analysis results map"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Associated session ID"
      ],
      duration_ms: [
        type: :integer,
        required: false,
        doc: "Analysis duration in milliseconds"
      ]
    ]
end
