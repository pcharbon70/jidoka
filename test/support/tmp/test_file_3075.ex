defmodule TestBehaviour do
  @callback init(term) :: {:ok, term} | {:error, term}
  @callback handle(term) :: term
end
