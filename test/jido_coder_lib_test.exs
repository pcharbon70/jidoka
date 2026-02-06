defmodule JidoCoderLibTest do
  use ExUnit.Case
  doctest JidoCoderLib

  test "greets the world" do
    assert JidoCoderLib.hello() == :world
  end
end
