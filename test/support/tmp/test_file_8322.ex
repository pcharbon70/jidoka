defmodule TestProtocol do
  @doc "Processes a value"
  def process(value)
end

defmodule StringImpl do
  def process(str), do: String.upcase(str)
end
