defmodule TestModule do
  @moduledoc """
  A test module for indexing.
  """

  @doc "Says hello"
  def hello(name) do
    "Hello, #{name}!"
  end

  defp private_helper, do: :ok
end
