defmodule JidokaTest do
  use ExUnit.Case
  doctest Jidoka

  test "greets the world" do
    assert Jidoka.hello() == :world
  end
end
