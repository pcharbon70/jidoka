# Jidoka

**Jidoka** — a Japanese word translating to "Automation with a human touch"

A **headless, client-agnostic agentic coding assistant core** built on Elixir and the BEAM VM.

## Overview

Jidoka provides the foundational architecture for building intelligent coding assistants. It features:

- **Multi-session workspaces** - Isolated concurrent coding sessions
- **Two-tier memory system** - Short-term context and persistent semantic memory
- **Knowledge graph layer** - SPARQL-based semantic code understanding
- **Pluggable protocols** - MCP, Phoenix Channels, and A2A integrations
- **Client-agnostic design** - TUI, Web, API, or custom clients

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   CLIENT LAYER (Pluggable)                  │
│   TUI │ Web │ API │ Custom - all connect via same API       │
├─────────────────────────────────────────────────────────────┤
│                   AGENT LAYER (Jido)                        │
│   Coordinator │ SessionManager │ LLM │ Context │ Analysis   │
├─────────────────────────────────────────────────────────────┤
│                 KNOWLEDGE GRAPH LAYER                       │
│   SPARQL Client │ Quad Store │ Named Graphs                 │
├─────────────────────────────────────────────────────────────┤
│                   PROTOCOL LAYER                            │
│   MCP │ Phoenix Channels │ A2A │ File Watch                 │
└─────────────────────────────────────────────────────────────┘
```

## Installation

> **Note**: This is currently under active development. The API is not yet stable.

Add `jidoka` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jidoka, "~> 0.1.0"}
  ]
end
```

## Development

### Requirements

- Elixir ~> 1.18
- Erlang/OTP 27+

### Setup

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Compile
mix compile
```

## Project Status

This project is currently in the **foundation phase**. See `notes/planning/01-foundation/` for the implementation plan.

## License

MIT License

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/jidoka) (once published).
