defmodule JidoCoderLib.Signals.FileChanged do
  @moduledoc """
  Signal emitted when a file system change is detected.

  This signal follows the CloudEvents v1.0.2 specification and is used
  to notify agents about file modifications, creations, or deletions.

  ## Fields

  - `:path` - Absolute path to the changed file (required)
  - `:action` - Type of change: `:created`, `:updated`, or `:deleted` (required)
  - `:session_id` - Optional session ID tracking the change
  - `:metadata` - Additional metadata about the file change

  ## Examples

      iex> {:ok, signal} = JidoCoderLib.Signals.FileChanged.new(%{
      ...>   path: "/path/to/file.ex",
      ...>   action: :updated
      ...> })
      iex> signal.type
      "jido_coder.file.changed"

      iex> {:ok, signal} = JidoCoderLib.Signals.FileChanged.new(%{
      ...>   path: "/path/to/file.ex",
      ...>   action: :created,
      ...>   session_id: "session-123",
      ...>   metadata: %{size: 1024}
      ...> })

  """

  use Jido.Signal,
    type: "jido_coder.file.changed",
    default_source: "/jido_coder/filesystem",
    schema: [
      path: [
        type: :string,
        required: true,
        doc: "Absolute path to the changed file"
      ],
      action: [
        type: :atom,
        required: true,
        doc: "Type of change: :created, :updated, or :deleted"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Session ID tracking the change"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Additional metadata about the file change"
      ]
    ]
end
