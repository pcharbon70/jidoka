defmodule JidoCoderLib.Jido do
  @moduledoc """
  Jido instance for jido_coder_lib.

  This module is the Jido supervisor that manages the lifecycle of
  agents in the application. It provides:
  - Agent server management
  - Registry for agent registration
  - Scoping for agent operations

  ## Usage

  Add this module to your application's supervision tree:

      children = [
        JidoCoderLib.Jido,
        # ... other children
      ]

  ## Starting Agents

  Use the Jido instance methods to start agents:

      {:ok, pid} = JidoCoderLib.Jido.start_agent(MyAgent, id: "my-agent")

  """

  use Jido, otp_app: :jido_coder_lib
end
