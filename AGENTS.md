# Repository Guidelines

## Project Structure & Module Organization
Core code lives in `lib/jidoka/`, organized by domain: `agents/`, `memory/`, `knowledge/`, `protocol/`, `session/`, `signals/`, and `tools/`. Keep new modules in the closest matching domain and expose stable APIs through `Jidoka.*` modules.  
Tests mirror source layout under `test/jidoka/**` (for example, `lib/jidoka/session/state.ex` -> `test/jidoka/session/state_test.exs`).  
Configuration is environment-scoped in `config/config.exs`, `config/dev.exs`, `config/test.exs`, and `config/prod.exs`.  
Architecture and implementation notes live in `guides/developer/` and `notes/`. Ontology assets are in `priv/ontologies/`.

## Build, Test, and Development Commands
Use Elixir `~> 1.18` and OTP `27+`.

- `mix deps.get` - Fetch dependencies.
- `mix compile` - Compile project code.
- `mix test` - Run default test suite.
- `mix test test/jidoka/session/state_test.exs` - Run a focused test file.
- `mix test --include knowledge_graph_required` - Include tests excluded by default in `test/test_helper.exs`.
- `mix format <files>` - Format changed files before opening a PR.

Note: `mix.exs` includes local path dependencies (`../jido_ai`, `../../elixir-ontologies`, `/home/ducky/code/triple_store`); update paths for your machine before first build.

## Coding Style & Naming Conventions
Follow standard Elixir style: 2-space indentation, snake_case function/file names, PascalCase modules, and explicit, small functions.  
Name modules by domain and responsibility (`Jidoka.Protocol.MCP.*`, `Jidoka.Memory.*`).  
Use clear `@moduledoc`/`@doc` text for public modules and functions.

## Testing Guidelines
This project uses ExUnit. Place unit tests beside related domains and name files `*_test.exs`.  
Prefer `describe` blocks and behavior-focused test names (for example, `"returns error for non-existent session"`).  
Use `async: true` when isolation allows it; switch to `async: false` for shared state, registries, or supervision tests.

## Commit & Pull Request Guidelines
Recent history uses short imperative subjects (for example, `Implement Phase 8.8: LLM Agent with Tool Calling`, `Fix compilation warnings`). Keep that style and make commits in logical chunks.  
PRs should include:
- concise summary of behavior changes,
- linked issue/task (if available),
- test evidence (`mix test` scope you ran),
- docs updates when behavior or architecture changes (`guides/developer/` or `notes/`).
