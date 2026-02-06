defmodule CodeSample.SimpleModule do
  @moduledoc """
  A simple module for testing code indexing.
  """

  @type user_id() :: integer()

  @doc """
  Greets the given name.
  """
  @spec greet(String.t()) :: String.t()
  def greet(name) do
    "Hello, #{name}!"
  end

  @doc """
  Adds two numbers together.
  """
  def add(a, b) do
    a + b
  end

  defp private_helper do
    :private
  end
end
