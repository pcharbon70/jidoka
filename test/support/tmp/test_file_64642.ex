defmodule TestStruct do
  defstruct [:name, :age, :email]

  def new(attrs) do
    struct!(__MODULE__, attrs)
  end
end
