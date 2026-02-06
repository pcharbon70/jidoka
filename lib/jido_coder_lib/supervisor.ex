defmodule JidoCoderLib.Supervisor do
  @moduledoc """
  The top-level supervisor for JidoCoderLib.

  This supervisor manages all core infrastructure components of the application.
  It uses a `:one_for_one` strategy, meaning that if a child process crashes,
  only that process is restarted.

  ## Supervised Children

  The following children are started by the Application module and supervised here:

  * `JidoCoderLib.ProtocolSupervisor` - Dynamic supervisor for protocol connections

  ## Future Children

  As phases are implemented, additional children will be added:
  * Phoenix PubSub (Phase 1.3)
  * AgentRegistry and TopicRegistry (Phase 1.4)
  * ContextStore (Phase 1.5)
  * Knowledge supervisor (Phase 1.7)
  * Agent supervisor (Phase 2.3)

  ## Supervisor Strategy

  The `:one_for_one` strategy is used because:
  * Children are independent - one child's failure doesn't affect others
  * We want to restart only the failed child, not the entire tree
  * This is the default and most common strategy for OTP applications
  """
end
