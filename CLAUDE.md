# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is **jidoka** - a research and planning repository for an agentic coding assistant system. The repository contains architectural documentation, agent system definitions, and command definitions for a sophisticated Elixir-based **headless** agentic coding assistant core.

**Important:** This repository primarily contains **documentation and agent/command definitions**, not executable code. The actual implementation is in separate repositories (jido_code_core, and potentially client implementations).

### Repository Structure

```
jidoka/
├── .claude/
│   ├── agent-definitions/    # Agent system definitions (elixir-expert, architecture-agent, etc.)
│   ├── commands/             # Command definitions (plan, execute, review, feature, etc.)
│   ├── AGENTS.md             # Agent orchestration system documentation
│   └── AGENT-SYSTEM-GUIDE.md # Model/tool optimization guide
└── research/                 # Architectural research and design documents
    ├── 1.00-architecture/    # Core architecture (agent layer + protocol layer)
    ├── 1.01-knowledge-base/  # Learning knowledge graph design
    ├── 1.03-extensibility/   # Commands, agents, skills, plugins system
    ├── 1.04-workflows/       # Workflow patterns
    ├── 1.05-context-management/ # Two-tier memory, context refinement
    ├── 1.06-tooling/         # Comprehensive tools reference
    ├── 1.07-memory-system/   # Two-tier memory architecture
    ├── 1.08-credo-rules/     # Semantic prevention system
    ├── 1.09-anti-patterns/   # Semantic anti-pattern prevention
    ├── 1.10-security/        # Security prevention system
    ├── 1.11-middleware/      # Unified code validation pipeline
    ├── 1.12-graph-of-thought/ # Graph of Thought reasoning
    ├── 1.13-prompt-management/ # User prompt design
    └── 1.14-project-split/   # Core library architecture with Client API
```

## Agent Orchestration System

This repository defines a comprehensive agent system for coordinating development work. The system uses specialized agents that must be consulted appropriately.

### Critical Agent Rules

**You are an Implementation Lead with Agent Guidance:**

- You are responsible for doing actual work (coding, writing, etc.)
- Consult specialized agents for expertise and patterns
- Never attempt Elixir work without consulting **elixir-expert** first
- Never commit work without running **elixir-reviewer** first

### Mandatory Agent Consultations

| Agent | When to Use | Purpose |
|-------|-------------|---------|
| **elixir-expert** | ALWAYS for Elixir/Phoenix/Ash work | Patterns, usage rules, documentation guidance |
| **architecture-agent** | Code placement, module organization | Structural guidance, integration patterns |
| **research-agent** | Unknown libraries, APIs, frameworks | Technical research and documentation |
| **elixir-reviewer** | AFTER any Elixir changes | Code quality, security, validation |
| **feature-planner** | Complex new features | Comprehensive planning with research |
| **fix-planner** | Bug fixes | Focused problem resolution plans |
| **task-planner** | Simple tasks | Lightweight overhead planning |

### Review Agents (Run in Parallel)

**ALWAYS run ALL review agents in parallel after implementation:**

```
PARALLEL EXECUTION:
├── factual-reviewer      # Implementation vs planning verification
├── qa-reviewer           # Test coverage and quality assurance
├── senior-engineer-reviewer # Architecture and design assessment
├── security-reviewer     # Security vulnerability analysis
├── consistency-reviewer  # Codebase pattern consistency
└── redundancy-reviewer   # Duplication and refactoring opportunities
```

## Four-Phase Workflow

For complex topics requiring comprehensive research:

```
1. /research   → Codebase impact analysis, third-party integration detection
2. /plan       → Feature specifications using discovered patterns
3. /breakdown  → Numbered checklists with granular implementation steps
4. /execute    → Sequential implementation following breakdown checklist
```

Output structure: `notes/[topic-name]/` folder with research.md, plan.md, breakdown.md

## Key Commands

### Planning Commands

- `/feature` - Uses **feature-planner** for comprehensive feature planning
- `/fix` - Uses **fix-planner** for bug fix planning
- `/task` - Uses **task-planner** for lightweight task planning
- `/plan` - Strategic implementation planning phase
- `/breakdown` - Task decomposition with numbered checklists
- `/execute` - Implementation execution following breakdown

### Workflow Commands

- `/research` - Codebase impact analysis and targeted documentation gathering
- `/implement` - Orchestrate implementation via implementation-agent
- `/review` - Run ALL review agents in parallel
- `/continue` - Continue work on current branch

### Other Commands

- `/commit` - Analyze changes and create commits
- `/pr` - Create GitHub pull request
- `/checkpoint` - Create recoverable checkpoint commit
- `/document` - Create documentation
- `/update-docs` - Update documentation
- `/add-tests` - Systematic test development
- `/fix-tests` - Test failure resolution
- `/cleanup` - Elixir project cleanup
- `/reflect` - Reflect on recent changes

## Elixir Development Guidelines

When working with Elixir code in related repositories:

### Code Style

- **Use `mix run` not `elixir`** for scripts in Mix projects
- **Use pipe operator only for multiple function calls** - single calls should be direct
- **Use `expect` not `stub`** for Mimic mocking
- **Use `mix ash.codegen`** for Ash resource migrations (not ecto.gen.migration)

### Phoenix/LiveView

- **ALWAYS create public wrapper functions** for LiveView components
- Use `attr` declarations for compile-time validation
- Example: `def user_card(assigns) do ... end` wrapping `<.live_component>`

### Testing

- Use generators for test setup, only call the action under test
- One action per test - no cascading actions
- Use `expect` for Mimic mocks (ensures mocks are actually called)

## Architecture Overview

The system is designed as a **headless, client-agnostic agentic core** with two primary layers:

1. **Agent Layer (Jido)** - GenServer-based agents with CloudEvents signals
2. **Protocol Layer** - MCP, Phoenix Channels, A2A gateway for external tools

3. **Client Layer (Pluggable)** - Any frontend (TUI, web, API, custom) connects via Client API

```
┌─────────────────────────────────────────────────────────────┐
│                   CLIENT LAYER (Pluggable)                  │
│   TUI │ Web │ API │ Custom - all connect via same API       │
├─────────────────────────────────────────────────────────────┤
│                   AGENT LAYER (Jido)                        │
│   Coordinator │ Context │ Code Analyzer │ LLM Agent         │
├─────────────────────────────────────────────────────────────┤
│                   PROTOCOL LAYER                            │
│   MCP │ Phoenix Channels │ A2A │ FS Watch                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

- **Process isolation** - Each agent runs as ~25KB process for fault tolerance
- **Phoenix PubSub backbone** - Decouples core from all clients
- **Jido Actions as LLM tools** - Unified abstraction for tool execution
- **Client-agnostic design** - Core has no knowledge of client implementation
- **Client API** - Well-defined PubSub event API for all clients

### Client API

Clients consume the core through:
1. **Direct function calls** - For commands (send message, start session)
2. **Phoenix PubSub events** - For receiving async updates

All clients subscribe to `"client.events"` topic to receive:
- `{:llm_stream_chunk, %{content: ...}}` - Streaming LLM responses
- `{:llm_response, %{content: ...}}` - Final LLM response
- `{:agent_status, %{status: ...}}` - Agent status updates
- `{:analysis_complete, %{results: ...}}` - Analysis results
- `{:tool_call, ...}` / `{:tool_result, ...}` - Tool execution

## Research Areas

The `/research` directory contains design documents for:

- **1.00-architecture** - Headless multi-agent architecture with Jido framework
- **1.01-knowledge-base** - Learning knowledge graph with SPARQL
- **1.03-extensibility** - Commands, agents, skills, plugins system
- **1.04-workflows** - Rainbow workflow patterns
- **1.05-context-management** - Two-tier memory, context refinement
- **1.06-tooling** - Comprehensive tools reference
- **1.07-memory-system** - Two-tier memory architecture
- **1.08-credo-rules** - Semantic prevention system
- **1.09-anti-patterns** - Semantic anti-pattern prevention
- **1.10-security** - Security prevention system
- **1.11-middleware** - Unified code validation pipeline
- **1.12-graph-of-thought** - Graph of Thought reasoning
- **1.13-prompt-management** - User prompt design
- **1.14-project-split** - Core library architecture with Client API

## Important Constraints

- **NEVER commit without asking** - Even if permission was previously given
- **NEVER merge git branches** - Not supported in workflow
- **NEVER mention AI in commit messages** - No Claude/AI references
- **NEVER use sycophantic language** - Direct, objective communication
- **ALWAYS show plan for confirmation** - Before implementing
- **Core is headless** - Architecture has no built-in UI; all clients are optional
