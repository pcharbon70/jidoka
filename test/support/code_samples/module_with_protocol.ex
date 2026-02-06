defmodule CodeSample.MathProtocol do
  @moduledoc """
  A protocol for math operations for testing code indexing.
  """

  @doc """
  Calculates the square of a value.
  """
  @callback square(number()) :: number()

  @doc """
  Calculates the cube of a value.
  """
  @callback cube(number()) :: number()
end

defmodule CodeSample.MathProtocol.IntegerImpl do
  @moduledoc """
  Implementation of MathProtocol for integers.
  """

  @behaviour CodeSample.MathProtocol

  @impl true
  def square(n), do: n * n

  @impl true
  def cube(n), do: n * n * n
end

defmodule CodeSample.MathProtocol.FloatImpl do
  @moduledoc """
  Implementation of MathProtocol for floats.
  """

  @behaviour CodeSample.MathProtocol

  @impl true
  def square(n), do: n * n

  @impl true
  def cube(n), do: n * n * n
end
