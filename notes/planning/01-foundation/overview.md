# Jido Coder Lib - Foundation Implementation Plan

## Overview

This implementation plan describes the construction of **jidoka**, a headless, client-agnostic agentic coding assistant core built on Elixir and the BEAM VM. The architecture follows a layered design with specialized agents, semantic memory systems, and pluggable protocol integrations.

## Architecture Diagram

```mermaid
graph TD
    subgraph ClientLayer [Client Layer]
        TUI[TUI Client]
        Web[Web Client]
        API[API Client]
    end

    subgraph AgentLayer [Agent Layer]
        Coordinator[Coordinator Agent]
        SessionManager[SessionManager Agent]
        CodeAnalyzer[Code Analyzer Agent]
        IssueDetector[Issue Detector Agent]

        subgraph WorkSessionA ["Work-Session A"]
            SessionSupervisorA[SessionSupervisor A]
            subgraph AgentsA ["Session A Agents"]
                LLMAgentA[LLM Agent A]
                ContextManagerA[ContextManager A]
                STMA[Short-Term Memory A]
            end
        end

        subgraph WorkSessionB ["Work-Session B"]
            SessionSupervisorB[SessionSupervisor B]
            subgraph AgentsB ["Session B Agents"]
                LLMAgentB[LLM Agent B]
                ContextManagerB[ContextManager B]
                STMB[Short-Term Memory B]
            end
        end
    end

    subgraph KnowledgeGraphLayer [Knowledge Graph Layer]
        SPARQLClient[SPARQL 1.1 Client Library]
        KGEngine[Knowledge-Graph Engine]

        subgraph NamedGraphs ["Named Graphs"]
            LTC_Graph["jido:long-term-context"]
            EC_Graph["jido:elixir-codebase"]
            CH_Graph["jido:conversation-history"]
            SK_Graph["jido:system-knowledge"]
        end
    end

    subgraph ProtocolLayer [Protocol Layer]
        MCP[MCP Client]
        PhoenixChannel[Phoenix Channel Client]
        A2AGateway[A2A Gateway]
        FSWatch[FS Watch Sensor]
    end

    subgraph CodeIndexing [Code Indexing]
        CodeIndexingProcess[Code Indexing Process]
    end

    %% Client to Agent Layer
    TUI -->|Phoenix PubSub| Coordinator
    Web -->|Phoenix PubSub| Coordinator
    API -->|Phoenix PubSub| Coordinator

    %% Agent Layer Internal
    Coordinator -->|Manages| SessionManager
    SessionManager -->|Creates/Manages| WorkSessionA
    SessionManager -->|Creates/Manages| WorkSessionB
    SessionSupervisorA -->|Supervises| AgentsA
    SessionSupervisorB -->|Supervises| AgentsB

    %% Agent to Knowledge Graph Layer
    LLMAgentA -->|Logs/Queries| SPARQLClient
    LLMAgentB -->|Logs/Queries| SPARQLClient
    ContextManagerA -->|Queries/Stores| SPARQLClient
    ContextManagerB -->|Queries/Stores| SPARQLClient
    CodeAnalyzer -->|Queries| SPARQLClient
    IssueDetector -->|Queries| SPARQLClient

    SPARQLClient -->|SPARQL| KGEngine
    KGEngine -->|Manages| NamedGraphs

    %% Code Indexing to Knowledge Graph Layer
    FSWatch -->|Detects Changes| CodeIndexingProcess
    CodeIndexingProcess -->|Populates| SPARQLClient

    %% Protocol Layer to Agents
    MCP -->|External Tools| Coordinator
    PhoenixChannel -->|Remote Events| Coordinator
    A2AGateway -->|Agent Comms| Coordinator
    FSWatch -->|File Events| CodeAnalyzer
```

## Project Structure

```
jidoka/
├── lib/
│   ├── jidoka/
│   │   ├── application.ex                 # Application entry point
│   │   ├── pubsub.ex                      # PubSub configuration
│   │   ├── agents/                        # Agent implementations
│   │   │   ├── coordinator.ex
│   │   │   ├── session_manager.ex
│   │   │   ├── context_manager.ex
│   │   │   ├── llm_orchestrator.ex
│   │   │   ├── code_analyzer.ex
│   │   │   └── issue_detector.ex
│   │   ├── session/                       # Session management
│   │   │   ├── supervisor.ex
│   │   │   └── state.ex
│   │   ├── memory/                        # Memory systems
│   │   │   ├── short_term/
│   │   │   │   ├── conversation_buffer.ex
│   │   │   │   ├── working_context.ex
│   │   │   │   └── pending_memories.ex
│   │   │   └── long_term/
│   │   │       ├── triple_store_adapter.ex
│   │   │       └── session_adapter.ex
│   │   ├── knowledge/                     # Knowledge graph layer
│   │   │   ├── sparql_client.ex
│   │   │   ├── named_graphs.ex
│   │   │   └── ontologies/
│   │   ├── tools/                         # Jido Actions as tools
│   │   │   ├── read_file.ex
│   │   │   ├── search_code.ex
│   │   │   └── analyze_function.ex
│   │   ├── protocol/                      # Protocol integrations
│   │   │   ├── mcp/
│   │   │   ├── phoenix/
│   │   │   └── a2a/
│   │   └── signals/                       # Signal definitions
│   └── jidoka.ex
├── test/
│   ├── jidoka/
│   │   ├── agents/
│   │   ├── session/
│   │   ├── memory/
│   │   ├── knowledge/
│   │   └── integration/
│   └── test_helper.ex
├── config/
│   ├── config.exs
│   └── dev.exs
├── mix.exs
└── README.md
```

## Phase Summaries

| Phase | Title | Description | Dependencies |
|-------|-------|-------------|--------------|
| 1 | Core Foundation | Application structure, supervision tree, PubSub, Registry | None |
| 2 | Agent Layer Base | Base agent abstractions, signal routing, coordinator | Phase 1 |
| 3 | Multi-Session Architecture | SessionManager, SessionSupervisor, isolated work-sessions | Phase 2 |
| 4 | Two-Tier Memory System | STM, LTM, promotion engine | Phase 3 |
| 5 | Knowledge Graph Layer | SPARQL client, quad store, named graphs | Phase 4 |
| 6 | Codebase Semantic Model | Elixir ontology, code indexing | Phase 5 |
| 7 | Conversation History | Conversation ontology, logging, retrieval | Phase 5 |
| 8 | Client API & Protocols | Client API, MCP, Phoenix Channels, A2A | Phase 7 |

## Implementation Principles

1. **Test-First**: Every component includes comprehensive tests before implementation
2. **Incremental**: Each phase builds on previous phases with clear dependencies
3. **Isolation**: Sessions are fully isolated with scoped state
4. **Semantic**: All knowledge is represented with proper ontologies
5. **Fault-Tolerant**: Leverages BEAM supervision for graceful degradation
6. **Client-Agnostic**: Core has no knowledge of client implementations

## Success Criteria

1. **Headless Operation**: Core runs without any UI client
2. **Multi-Session**: Multiple isolated sessions running concurrently
3. **Persistent Memory**: Two-tier memory with promotion and retrieval
4. **Semantic Code Understanding**: Codebase represented as queryable knowledge graph
5. **Conversation History**: Full interaction logging with structured ontology
6. **Protocol Support**: MCP, Phoenix Channels, and A2A integrations
7. **Client API**: Well-defined PubSub event API for any client type
8. **Test Coverage**: 80%+ test coverage across all modules
9. **Documentation**: Comprehensive module and function documentation
10. **Fault Tolerance**: Graceful handling of agent failures

## Phase Files

- [Phase 1: Core Foundation](./phase-01.md)
- [Phase 2: Agent Layer Base](./phase-02.md)
- [Phase 3: Multi-Session Architecture](./phase-03.md)
- [Phase 4: Two-Tier Memory System](./phase-04.md)
- [Phase 5: Knowledge Graph Layer](./phase-05.md)
- [Phase 6: Codebase Semantic Model](./phase-06.md)
- [Phase 7: Conversation History](./phase-07.md)
- [Phase 8: Client API & Protocols](./phase-08.md)
