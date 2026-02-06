defmodule CodeSample.ModuleWithDependencies do
  @moduledoc """
  A module that uses other modules for testing dependency tracking.
  """

  alias CodeSample.SimpleModule
  import CodeSample.MathProtocol.IntegerImpl

  def create_and_greet(name) do
    SimpleModule.greet(name)
  end

  def calculate_square(n) do
    square(n)
  end
end
