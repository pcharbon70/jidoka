defmodule CodeSample.ModuleWithStruct do
  @moduledoc """
  A module with a struct definition for testing code indexing.
  """

  defstruct name: nil,
            age: nil,
            email: nil,
            active: true

  @type t() :: %__MODULE__{
          name: String.t() | nil,
          age: non_neg_integer() | nil,
          email: String.t() | nil,
          active: boolean()
        }

  @doc """
  Creates a new user struct.
  """
  def new(name, age, email) do
    %__MODULE__{
      name: name,
      age: age,
      email: email,
      active: true
    }
  end

  @doc """
  Returns whether the user is active.
  """
  def active?(%__MODULE__{active: active}), do: active
end
