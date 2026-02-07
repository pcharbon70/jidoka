# Phase 8.7: Tool Definitions

**Branch:** `feature/phase-8.7-tool-definitions`
**Created:** 2026-02-07
**Status:** ✅ Complete

---

## Problem Statement

The LLM agent needs a standard set of tools to interact with the codebase. Currently, there are no Jido Actions defined for common code operations like reading files, searching code, analyzing functions, listing files, and getting definitions. Without these tools, the LLM cannot perform basic coding assistant tasks.

---

## Solution Overview

Created core tools as Jido Actions that:
1. **ReadFile** - Read file contents with line range support
2. **SearchCode** - Search for patterns across codebase using grep
3. **AnalyzeFunction** - Get function details from the knowledge graph
4. **ListFiles** - List directory contents with glob patterns
5. **GetDefinition** - Find module, function, struct definitions via LSP
6. **Tools.Registry** - Central registry for tool discovery
7. **Tool Schema Generation** - Convert Jido Actions to LLM function calling format

**Key Design Decisions:**
- Use `Jido.Action` for all tools (consistent with existing codebase)
- Tools delegate to existing modules (`Codebase.Queries`, `PathValidator`, etc.)
- Registry uses compile-time registration
- Schema generation follows OpenAI function calling format
- All tools include proper error handling and validation

---

## Files Created

| File | Lines | Description |
|------|-------|-------------|
| `lib/jidoka/tools/read_file.ex` | 159 | Read file contents with line range support |
| `lib/jidoka/tools/search_code.ex` | 152 | Search code patterns using grep |
| `lib/jidoka/tools/analyze_function.ex` | 76 | Get function details from knowledge graph |
| `lib/jidoka/tools/list_files.ex` | 136 | List directory contents with glob patterns |
| `lib/jidoka/tools/get_definition.ex` | 283 | Find definitions via knowledge graph |
| `lib/jidoka/tools/registry.ex` | 193 | Tool discovery and listing |
| `lib/jidoka/tools/schema.ex` | 180 | LLM function calling schema generation |

## Files Modified

| File | Changes |
|------|---------|
| `mix.exs` | Added Jason dependency for JSON encoding |
| `test/jidoka/tools_test.exs` | Comprehensive tool tests (new file, 313 lines) |

---

## Test Results

**All 24 non-knowledge-graph tests pass.**

7 tests requiring indexed knowledge graph are excluded by default (run with `--exclude knowledge_graph_required`).

```
Finished in 5.8 seconds (0.00s async, 5.8s sync)
31 tests, 0 failures, 7 excluded
```

---

## API Examples

```elixir
# Read a file
{:ok, result, []} = Jidoka.Tools.ReadFile.run(
  %{file_path: "lib/jidoka/client.ex", offset: 1, limit: 50},
  %{}
)

# Search code
{:ok, result, []} = Jidoka.Tools.SearchCode.run(
  %{pattern: "defmodule", file_pattern: "*.ex"},
  %{}
)

# Analyze function (requires indexed codebase)
{:ok, result, []} = Jidoka.Tools.AnalyzeFunction.run(
  %{module: "Jidoka.Client", function: "create_session", arity: 1},
  %{}
)

# List files
{:ok, result, []} = Jidoka.Tools.ListFiles.run(
  %{path: "lib/jidoka", pattern: "*.ex", recursive: true},
  %{}
)

# Get definition (requires indexed codebase)
{:ok, result, []} = Jidoka.Tools.GetDefinition.run(
  %{type: "module", name: "Jidoka.Client"},
  %{}
)

# List all tools
tools = Jidoka.Tools.Registry.list_tools()

# Generate LLM schema
schema = Jidoka.Tools.Schema.to_openai_schema(Jidoka.Tools.ReadFile)
```

---

## How to Test

```bash
# Run tests (knowledge graph tests excluded by default)
mix test test/jidoka/tools_test.exs --exclude knowledge_graph_required

# Run all tests including knowledge graph tests
mix test test/jidoka/tools_test.exs

# Test individual tools in iex
iex -S mix
Jidoka.Tools.ReadFile.run(%{file_path: "lib/jidoka/client.ex"}, %{})
```

---

## Notes/Considerations

1. **Path Security**: All file operations use `PathValidator` to prevent directory traversal
2. **Knowledge Graph**: Function/definition queries depend on indexed codebase
3. **Schema Format**: Follows OpenAI function calling JSON Schema format
4. **Error Handling**: Returns `{:error, reason}` tuples consistently
5. **Tool Discovery**: Registry uses compile-time registration via `@tools` attribute
6. **Jason Dependency**: Added `{:jason, "~> 1.4"}` for JSON encoding in Schema module
