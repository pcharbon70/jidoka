defmodule JidoCoderLib.Knowledge.Context do
  @moduledoc """
  Helper functions for working with Knowledge Engine execution contexts.

  This module provides utilities for preparing execution contexts that
  will be used with TripleStore SPARQL operations.

  ## permit_all Mode

  In quad schema with ACL (Access Control Lists), certain operations require
  bypassing authorization checks. This module provides a helper to enable
  permit_all mode for internal operations.

  ## Examples

      ctx = Engine.context(:knowledge_engine)
      ctx = Context.with_permit_all(ctx)

      # Use with TripleStore operations
      TripleStore.update(ctx, sparql_update)

  """

  alias JidoCoderLib.Knowledge.Engine

  @doc """
  Enables permit_all mode for a context, bypassing ACL checks.

  This is necessary for internal operations in quad schema where the
  application needs to bypass authorization checks.

  Sets both the process-level permit_all flag AND adds :permit_all to
  the context map. The TripleStore authorization checks for both.

  ## Parameters

  - `ctx` - Execution context map with `:db` and `:dict_manager` keys

  ## Returns

  - Context map with `:permit_all => true` added

  ## Examples

      ctx = Engine.context(:my_engine)
      ctx = Context.with_permit_all(ctx)
      #=> %{db: <ref>, dict_manager: <pid>, permit_all: true}

  """
  @spec with_permit_all(map()) :: map()
  def with_permit_all(ctx) do
    # Set process-level permit_all for authorization bypass
    TripleStore.SPARQL.Authorization.set_permit_all(true)

    # Also add permit_all to context (TripleStore checks both ctx[:permit_all] and process-level)
    Map.put(ctx, :permit_all, true)
  end

  @doc """
  Gets the execution context for a knowledge engine.

  Convenience function that combines getting the engine context
  with enabling permit_all mode.

  ## Parameters

  - `engine` - Engine PID or registered name

  ## Returns

  - Context map with `:db`, `:dict_manager`, and `:permit_all` keys

  ## Examples

      ctx = Context.engine_context(:knowledge_engine)

  """
  @spec engine_context(GenServer.server()) :: map()
  def engine_context(engine) when is_pid(engine) or is_atom(engine) do
    engine
    |> Engine.context()
    |> with_permit_all()
  end
end
