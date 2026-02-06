defmodule JidoCoderLib.Conversation do
  @moduledoc """
  Context module for conversation history functionality.

  This module provides the main API for working with conversation history
  in the knowledge graph. It includes functionality for:

  - Logging conversations, turns, prompts, and answers
  - Tracking tool invocations and results
  - Retrieving conversation history
  - Analyzing conversation patterns

  ## Architecture

  The conversation system is organized into sub-modules:

  | Module | Purpose |
  |--------|---------|
  | `JidoCoderLib.Conversation.Logger` | Logging conversations to the knowledge graph |
  | `JidoCoderLib.Conversation.Retrieval` | Querying and retrieving conversation history |
  | `JidoCoderLib.Conversation.Analysis` | Analyzing conversation patterns |

  ## Conversation Graph

  All conversation data is stored in the `:conversation_history` named graph,
  separate from other knowledge graphs like `:long_term_context` and `:system_knowledge`.

  ## Ontology

  The conversation system uses the Conversation History ontology
  (see `priv/ontologies/conversation-history.ttl`) which defines:

  - `:Conversation` - A sequence of conversation turns
  - `:ConversationTurn` - A single prompt-answer cycle
  - `:Prompt` - User input text
  - `:Answer` - Assistant response text
  - `:ToolInvocation` - Tool call with parameters
  - `:ToolResult` - Tool outcome

  ## Examples

  Start logging a conversation:

      {:ok, conversation_iri} = Conversation.Logger.ensure_conversation("session-123")

      {:ok, _turn} = Conversation.Logger.log_turn(conversation_iri, 0)
      {:ok, _prompt} = Conversation.Logger.log_prompt(conversation_iri, 0, "Hello!")
      {:ok, _answer} = Conversation.Logger.log_answer(conversation_iri, 0, "Hi there!")

  """

  @type conversation_iri :: String.t()
  @type turn_iri :: String.t()
  @type session_id :: String.t()
end
