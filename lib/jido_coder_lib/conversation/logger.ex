defmodule JidoCoderLib.Conversation.Logger do
  @moduledoc """
  Logs conversation interactions to the knowledge graph.

  This module provides functions for recording all components of a conversation
  including prompts, answers, tool invocations, and tool results. All data is
  stored in the `:conversation_history` named graph using the Conversation
  History ontology.

  ## Graph

  All conversation data is stored in the `:conversation_history` named graph:
  `https://jido.ai/graphs/conversation-history`

  ## Functions

  - `ensure_conversation/2` - Create or get a conversation for a session
  - `log_turn/3` - Log a conversation turn
  - `log_prompt/3` - Log a user prompt
  - `log_answer/3` - Log an assistant answer
  - `log_tool_invocation/4` - Log a tool invocation with parameters
  - `log_tool_result/4` - Log a tool result

  ## Examples

      {:ok, conversation_iri} = Logger.ensure_conversation("session-123")

      {:ok, turn_iri} = Logger.log_turn(conversation_iri, 0)
      {:ok, prompt_iri} = Logger.log_prompt(conversation_iri, 0, "What is Elixir?")
      {:ok, answer_iri} = Logger.log_answer(conversation_iri, 0, "Elixir is...")

      # With tools
      params = %{"query" => "SELECT *"}
      {:ok, invocation_iri} = Logger.log_tool_invocation(conversation_iri, 0, 0, "sparql_query", params)
      {:ok, result_iri} = Logger.log_tool_result(conversation_iri, 0, 0, %{"rows" => 5})

  """

  alias JidoCoderLib.Knowledge.{Engine, Ontology, NamedGraphs, Context}
  import TripleStore, only: [update: 2]

  # Prefixes for SPARQL queries
  @prefix_jido "https://jido.ai/ontology#"
  @prefix_conv "https://jido.ai/ontology/conversation-history#"
  @prefix_xsd "http://www.w3.org/2001/XMLSchema#"

  # ========================================================================
  # Public API - Conversation Management
  # ========================================================================

  @doc """
  Ensures a conversation exists for the given session.

  If a conversation already exists for this session, returns its IRI.
  Otherwise, creates a new conversation individual in the knowledge graph.

  ## Parameters

  - `session_id` - Unique identifier for the session
  - `opts` - Optional keyword list:
    - `:metadata` - Map of additional metadata to attach (default: %{})

  ## Returns

  - `{:ok, conversation_iri}` - Conversation created or found
  - `{:error, reason}` - Failed to create conversation

  ## Examples

      {:ok, iri} = Logger.ensure_conversation("session-123")
      {:ok, iri} = Logger.ensure_conversation("session-123", metadata: %{"source" => "cli"})

  """
  @spec ensure_conversation(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ensure_conversation(session_id, opts \\ []) when is_binary(session_id) do
    conversation_iri = Ontology.create_conversation_individual(session_id)

    # Check if conversation already exists by attempting to query for it
    # If it doesn't exist, create it
    case conversation_exists?(conversation_iri) do
      true ->
        {:ok, conversation_iri}

      false ->
        create_conversation(conversation_iri, session_id, opts)
    end
  end

  @doc """
  Logs a conversation turn.

  Creates a ConversationTurn individual linked to the parent conversation.

  ## Parameters

  - `conversation_iri` - IRI of the parent conversation
  - `turn_index` - Zero-based index of the turn
  - `opts` - Optional keyword list:
    - `:timestamp` - DateTime for the turn (default: DateTime.utc_now())

  ## Returns

  - `{:ok, turn_iri}` - Turn logged successfully
  - `{:error, reason}` - Failed to log turn

  ## Examples

      {:ok, iri} = Logger.log_turn(conversation_iri, 0)

  """
  @spec log_turn(String.t(), non_neg_integer(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def log_turn(conversation_iri, turn_index, opts \\ []) do
    turn_iri = extract_conversation_id(conversation_iri) |> Ontology.create_conversation_turn_individual(turn_index)
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    sparql = build_turn_insert(turn_iri, conversation_iri, turn_index, timestamp)

    execute_update(sparql, turn_iri)
  end

  @doc """
  Logs a user prompt.

  Creates a Prompt individual with the given text content.

  ## Parameters

  - `conversation_iri` - IRI of the parent conversation
  - `turn_index` - Zero-based index of the associated turn
  - `prompt_text` - Text content of the prompt
  - `opts` - Optional keyword list:
    - `:timestamp` - DateTime for the prompt (default: DateTime.utc_now())

  ## Returns

  - `{:ok, prompt_iri}` - Prompt logged successfully
  - `{:error, reason}` - Failed to log prompt

  ## Examples

      {:ok, iri} = Logger.log_prompt(conversation_iri, 0, "What is Elixir?")

  """
  @spec log_prompt(String.t(), non_neg_integer(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def log_prompt(conversation_iri, turn_index, prompt_text, opts \\ [])
      when is_binary(conversation_iri) and is_integer(turn_index) do
    prompt_iri = extract_conversation_id(conversation_iri) |> Ontology.create_prompt_individual(turn_index)
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    sparql = build_prompt_insert(prompt_iri, turn_index, prompt_text, timestamp)

    execute_update(sparql, prompt_iri)
  end

  @doc """
  Logs an assistant answer.

  Creates an Answer individual with the given text content.

  ## Parameters

  - `conversation_iri` - IRI of the parent conversation
  - `turn_index` - Zero-based index of the associated turn
  - `answer_text` - Text content of the answer
  - `opts` - Optional keyword list:
    - `:timestamp` - DateTime for the answer (default: DateTime.utc_now())

  ## Returns

  - `{:ok, answer_iri}` - Answer logged successfully
  - `{:error, reason}` - Failed to log answer

  ## Examples

      {:ok, iri} = Logger.log_answer(conversation_iri, 0, "Elixir is...")

  """
  @spec log_answer(String.t(), non_neg_integer(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def log_answer(conversation_iri, turn_index, answer_text, opts \\ [])
      when is_binary(conversation_iri) and is_integer(turn_index) do
    answer_iri = extract_conversation_id(conversation_iri) |> Ontology.create_answer_individual(turn_index)
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    sparql = build_answer_insert(answer_iri, turn_index, answer_text, timestamp)

    execute_update(sparql, answer_iri)
  end

  @doc """
  Logs a tool invocation.

  Creates a ToolInvocation individual with the given tool name and parameters.

  ## Parameters

  - `conversation_iri` - IRI of the parent conversation
  - `turn_index` - Zero-based index of the associated turn
  - `tool_index` - Zero-based index of the tool within this turn
  - `tool_name` - Name/identifier of the tool being invoked
  - `parameters` - Map of parameters to pass to the tool
  - `opts` - Optional keyword list:
    - `:timestamp` - DateTime for the invocation (default: DateTime.utc_now())

  ## Returns

  - `{:ok, invocation_iri}` - Invocation logged successfully
  - `{:error, reason}` - Failed to log invocation

  ## Examples

      {:ok, iri} = Logger.log_tool_invocation(
        conversation_iri,
        0,
        0,
        "sparql_query",
        %{"query" => "SELECT *"}
      )

  """
  @spec log_tool_invocation(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          String.t(),
          map() | nil,
          keyword()
        ) :: {:ok, String.t()} | {:error, term()}
  def log_tool_invocation(conversation_iri, turn_index, tool_index, tool_name, parameters, opts \\ [])
      when is_binary(conversation_iri) and is_integer(turn_index) and is_integer(tool_index) and
             is_binary(tool_name) do
    invocation_iri =
      extract_conversation_id(conversation_iri)
      |> Ontology.create_tool_invocation_individual(turn_index, tool_index)

    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    sparql =
      build_tool_invocation_insert(invocation_iri, turn_index, tool_name, parameters, timestamp)

    execute_update(sparql, invocation_iri)
  end

  @doc """
  Logs a tool result.

  Creates a ToolResult individual with the given result data.

  ## Parameters

  - `conversation_iri` - IRI of the parent conversation
  - `turn_index` - Zero-based index of the associated turn
  - `tool_index` - Zero-based index of the tool within this turn
  - `result_data` - Map of result data from the tool
  - `opts` - Optional keyword list:
    - `:timestamp` - DateTime for the result (default: DateTime.utc_now())

  ## Returns

  - `{:ok, result_iri}` - Result logged successfully
  - `{:error, reason}` - Failed to log result

  ## Examples

      {:ok, iri} = Logger.log_tool_result(
        conversation_iri,
        0,
        0,
        %{"status" => "success", "rows" => 5}
      )

  """
  @spec log_tool_result(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          map() | nil,
          keyword()
        ) :: {:ok, String.t()} | {:error, term()}
  def log_tool_result(conversation_iri, turn_index, tool_index, result_data, opts \\ [])
      when is_binary(conversation_iri) and is_integer(turn_index) and is_integer(tool_index) do
    result_iri =
      extract_conversation_id(conversation_iri)
      |> Ontology.create_tool_result_individual(turn_index, tool_index)

    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    sparql = build_tool_result_insert(result_iri, turn_index, tool_index, result_data, timestamp)

    execute_update(sparql, result_iri)
  end

  # ========================================================================
  # Private Helpers - SPARQL Building
  # ========================================================================

  defp build_turn_insert(turn_iri, conversation_iri, turn_index, timestamp) do
    formatted_ts = format_timestamp(timestamp)
    conversation_id_iri = "<#{conversation_iri}>"

    """
    PREFIX jido: <#{@prefix_jido}>
    PREFIX conv: <#{@prefix_conv}>
    PREFIX xsd: <#{@prefix_xsd}>

    INSERT DATA {
      GRAPH <#{graph_iri_string()}> {
        <#{turn_iri}> a conv:ConversationTurn ;
            conv:partOfConversation #{conversation_id_iri} ;
            conv:turnIndex #{turn_index} ;
            conv:timestamp "#{formatted_ts}"^^xsd:dateTime .

        #{conversation_id_iri} conv:hasTurn <#{turn_iri}> .
      }
    }
    """
  end

  defp build_prompt_insert(prompt_iri, turn_index, prompt_text, timestamp) do
    formatted_ts = format_timestamp(timestamp)
    escaped_text = escape_string(prompt_text)

    # Get turn IRI for linking
    conversation_id = extract_conversation_id_from_iri(prompt_iri)
    turn_iri = "<#{Ontology.create_conversation_turn_individual(conversation_id, turn_index)}>"

    """
    PREFIX conv: <#{@prefix_conv}>
    PREFIX xsd: <#{@prefix_xsd}>

    INSERT DATA {
      GRAPH <#{graph_iri_string()}> {
        <#{prompt_iri}> a conv:Prompt ;
            conv:promptText "#{escaped_text}" ;
            conv:timestamp "#{formatted_ts}"^^xsd:dateTime .

        #{turn_iri} conv:hasPrompt <#{prompt_iri}> .
      }
    }
    """
  end

  defp build_answer_insert(answer_iri, turn_index, answer_text, timestamp) do
    formatted_ts = format_timestamp(timestamp)
    escaped_text = escape_string(answer_text)

    # Get turn IRI for linking
    conversation_id = extract_conversation_id_from_iri(answer_iri)
    turn_iri = "<#{Ontology.create_conversation_turn_individual(conversation_id, turn_index)}>"

    """
    PREFIX conv: <#{@prefix_conv}>
    PREFIX xsd: <#{@prefix_xsd}>

    INSERT DATA {
      GRAPH <#{graph_iri_string()}> {
        <#{answer_iri}> a conv:Answer ;
            conv:answerText "#{escaped_text}" ;
            conv:timestamp "#{formatted_ts}"^^xsd:dateTime .

        #{turn_iri} conv:hasAnswer <#{answer_iri}> .
      }
    }
    """
  end

  defp build_tool_invocation_insert(invocation_iri, turn_index, tool_name, parameters, timestamp) do
    formatted_ts = format_timestamp(timestamp)
    escaped_name = escape_string(tool_name)
    params_json = encode_json(parameters)

    # Get turn IRI for linking
    conversation_id = extract_conversation_id_from_iri(invocation_iri)
    turn_iri = "<#{Ontology.create_conversation_turn_individual(conversation_id, turn_index)}>"

    # Build triple content - conditionally include parameters
    triples_content = [
      "conv:toolName \"#{escaped_name}\"",
      if(params_json != "", do: "conv:invocationParameters \"#{params_json}\"", else: ""),
      "conv:timestamp \"#{formatted_ts}\"^^xsd:dateTime"
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ;\n    ")

    """
    PREFIX conv: <#{@prefix_conv}>
    PREFIX xsd: <#{@prefix_xsd}>

    INSERT DATA {
      GRAPH <#{graph_iri_string()}> {
        <#{invocation_iri}> a conv:ToolInvocation ;
            #{triples_content} .

        #{turn_iri} conv:involvesToolInvocation <#{invocation_iri}> .
      }
    }
    """
  end

  defp build_tool_result_insert(result_iri, turn_index, tool_index, result_data, timestamp) do
    formatted_ts = format_timestamp(timestamp)
    result_json = encode_json(result_data)

    # Get tool invocation IRI for linking
    conversation_id = extract_conversation_id_from_iri(result_iri)
    invocation_iri =
      "<#{Ontology.create_tool_invocation_individual(conversation_id, turn_index, tool_index)}>"

    # Build triple content - conditionally include result data
    triples_content = [
      if(result_json != "", do: "conv:resultData \"#{result_json}\"", else: ""),
      "conv:timestamp \"#{formatted_ts}\"^^xsd:dateTime"
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ;\n    ")

    """
    PREFIX conv: <#{@prefix_conv}>
    PREFIX xsd: <#{@prefix_xsd}>

    INSERT DATA {
      GRAPH <#{graph_iri_string()}> {
        <#{result_iri}> a conv:ToolResult ;
            #{triples_content} .

        #{invocation_iri} conv:hasResult <#{result_iri}> .
      }
    }
    """
  end

  # ========================================================================
  # Private Helpers - Conversation Creation
  # ========================================================================

  defp create_conversation(conversation_iri, session_id, opts) do
    metadata = Keyword.get(opts, :metadata, %{})
    now = DateTime.utc_now() |> format_timestamp()

    # Extract conversation ID for session IRI
    session_iri = "https://jido.ai/sessions\##{session_id}"

    # Build metadata triples
    metadata_triples =
      Enum.map(metadata, fn {key, value} ->
        "    <#{conversation_iri}> jido:metadata \"#{escape_string("#{key}: #{value}")}\" ."
      end)
      |> Enum.join("\n")

    sparql = """
    PREFIX jido: <#{@prefix_jido}>
    PREFIX conv: <#{@prefix_conv}>
    PREFIX xsd: <#{@prefix_xsd}>

    INSERT DATA {
      GRAPH <#{graph_iri_string()}> {
        <#{conversation_iri}> a conv:Conversation ;
            jido:sessionId "#{session_id}" ;
            conv:associatedWithSession <#{session_iri}> ;
            conv:timestamp "#{now}"^^xsd:dateTime .
    #{if metadata_triples != "", do: "\n" <> metadata_triples, else: ""}
      }
    }
    """

    execute_update(sparql, conversation_iri)
  end

  defp conversation_exists?(conversation_iri) do
    sparql = """
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

    ASK {
      GRAPH <#{graph_iri_string()}> {
        <#{conversation_iri}> a ?type .
      }
    }
    """

    ctx = engine_context()

    case TripleStore.SPARQL.Query.query(ctx, sparql) do
      {:ok, %{results: [[true]]}} -> true
      _ -> false
    end
  end

  # ========================================================================
  # Private Helpers - Utilities
  # ========================================================================

  defp execute_update(sparql, iri) do
    ctx = engine_context()

    case update(ctx, sparql) do
      {:ok, _count} -> {:ok, iri}
      {:error, reason} -> {:error, reason}
    end
  end

  defp engine_context do
    engine_name()
    |> Engine.context()
    |> Map.put(:transaction, nil)
    |> Context.with_permit_all()
  end

  defp engine_name do
    Application.get_env(:jido_coder_lib, :knowledge_engine_name, :knowledge_engine)
  end

  defp graph_iri_string do
    {:ok, iri_string} = NamedGraphs.iri_string(:conversation_history)
    iri_string
  end

  defp format_timestamp(%DateTime{} = dt) do
    DateTime.to_iso8601(dt, :extended)
  end

  defp escape_string(nil), do: ""
  defp escape_string(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp encode_json(nil), do: ""
  defp encode_json(data) when is_map(data) or is_list(data) do
    case Jason.encode(data) do
      {:ok, json} -> escape_string(json)
      _ -> ""
    end
  end

  # Extract conversation ID from conversation IRI
  # e.g., "https://jido.ai/conversations#conv-123" -> "conv-123"
  defp extract_conversation_id(conversation_iri) do
    conversation_iri
    |> String.split("#")
    |> List.last()
  end

  # Extract conversation ID from any individual IRI
  # e.g., "https://jido.ai/conversations#conv-123/turn-0/prompt" -> "conv-123"
  defp extract_conversation_id_from_iri(iri) do
    iri
    |> String.split("#")
    |> List.last()
    |> String.split("/")
    |> List.first()
  end
end
