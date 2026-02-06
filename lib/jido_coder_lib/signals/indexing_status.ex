defmodule JidoCoderLib.Signals.IndexingStatus do
  @moduledoc """
  Signal emitted when code indexing status changes.

  This signal follows the CloudEvents v1.0.2 specification and is used
  to notify agents about changes to file indexing operations.

  ## Fields

  - `:file_path` - Path to the file being indexed (required)
  - `:status` - Current indexing status (required)
  - `:project_root` - Root directory of the project
  - `:triple_count` - Number of triples generated (for completed operations)
  - `:error_message` - Error message (for failed operations)
  - `:duration_ms` - Duration of the indexing operation in milliseconds

  ## Status Values

  - `:pending` - Operation is queued
  - `:in_progress` - Operation is currently running
  - `:completed` - Operation completed successfully
  - `:failed` - Operation failed

  ## Examples

      iex> {:ok, signal} = JidoCoderLib.Signals.IndexingStatus.new(%{
      ...>   file_path: "lib/my_app.ex",
      ...>   status: :in_progress
      ...> })
      iex> signal.type
      "jido_coder.indexing.status"

      iex> {:ok, signal} = JidoCoderLib.Signals.IndexingStatus.new(%{
      ...>   file_path: "lib/my_app.ex",
      ...>   status: :completed,
      ...>   triple_count: 42,
      ...>   duration_ms: 150
      ...> })

  """

  use Jido.Signal,
    type: "jido_coder.indexing.status",
    default_source: "/jido_coder/indexing",
    schema: [
      file_path: [
        type: :string,
        required: true,
        doc: "Path to the file being indexed"
      ],
      status: [
        type: :atom,
        required: true,
        doc: "Current indexing status: :pending, :in_progress, :completed, or :failed"
      ],
      project_root: [
        type: :string,
        required: false,
        doc: "Root directory of the project"
      ],
      triple_count: [
        type: :integer,
        required: false,
        doc: "Number of triples generated (for completed operations)"
      ],
      error_message: [
        type: :string,
        required: false,
        doc: "Error message (for failed operations)"
      ],
      duration_ms: [
        type: :integer,
        required: false,
        doc: "Duration of the indexing operation in milliseconds"
      ]
    ]
end
