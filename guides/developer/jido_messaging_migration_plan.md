# Jido Messaging Migration Plan

## Goal
Replace Jidoka's current session/tracker/signal conversation pipeline with `jido_messaging` as the canonical conversation runtime.

This plan assumes a greenfield migration target with **no backward compatibility requirements**.

## Status Snapshot (2026-02-15)
- Phase 1: Completed
- Phase 2: Completed
- Phase 3: Completed (projection path is active for graph logging)
- Phase 4: In progress
  - Completed:
    - Removed `Conversation.Tracker` runtime
    - `Jidoka.Client.send_message/3` now persists via `Jidoka.Messaging`
    - `ContextManager` conversation APIs now read/write from `Jidoka.Messaging`
    - Session conversation events are published from `Jidoka.Messaging.append_session_message/4`
  - Remaining:
    - Remove legacy session runtime modules (`SessionManager`, `Session.Supervisor`, session state/persistence)
    - Remove remaining conversation responsibilities from `ContextManager` (keep only non-conversation context concerns or replace it)
    - Replace conversation-specific PubSub/session routing with messaging-native subscriptions where applicable
- Phase 5: In progress (tests/docs cleanup underway)

## Current Conversation System (To Replace)
- Session lifecycle and ETS state: `lib/jidoka/agents/session_manager.ex`
- Per-session runtime: `lib/jidoka/session/supervisor.ex`
- Conversation identity and turn counters: `lib/jidoka/conversation/tracker.ex`
- Conversation write model (KG): `lib/jidoka/conversation/logger.ex`
- Chat routing: `lib/jidoka/agents/coordinator/actions/handle_chat_request.ex`
- LLM request/response orchestration: `lib/jidoka/agents/llm_orchestrator/actions/handle_llm_request.ex`, `lib/jidoka/agents/llm_orchestrator/actions/handle_llm_response.ex`
- Tool logging actions: `lib/jidoka/agents/llm_orchestrator/actions/handle_tool_call.ex`, `lib/jidoka/agents/llm_orchestrator/actions/handle_tool_result.ex`
- Conversation logging action: `lib/jidoka/agents/coordinator/actions/log_conversation_turn.ex`
- Session/topic routing wrapper: `lib/jidoka/pubsub.ex`

## Target System
- Canonical conversation entities: `JidoMessaging.Room`, `JidoMessaging.Participant`, `JidoMessaging.Message`
- Canonical ingress: `JidoMessaging.Ingest`
- Canonical egress: `JidoMessaging.Deliver` + `JidoMessaging.OutboundGateway`
- Canonical runtime supervision: `Jidoka.Messaging` (`use JidoMessaging`)
- Session identity handling becomes room binding metadata (no separate tracker process).

## Phase Plan

### Phase 1 - Foundation (Completed in this scaffold)
- Added `lib/jidoka/messaging.ex` with `use JidoMessaging`.
- Added `Jidoka.Messaging` to app supervision in `lib/jidoka/application.ex`.
- Added initial room mapping helpers (`session_id` -> room binding) and session message helpers in `lib/jidoka/messaging.ex`.

### Phase 2 - Request Routing Cutover (Completed)
- Modify `lib/jidoka/agents/coordinator/actions/handle_chat_request.ex`:
  - Stop deriving `conversation_iri` from `Conversation.Tracker`.
  - Resolve/create room via `Jidoka.Messaging.ensure_room_for_session/1`.
  - Persist incoming user message through `Jidoka.Messaging.append_session_message/4` (or direct `Ingest` integration if channelized).
- Modify `lib/jidoka/agents/llm_orchestrator/actions/handle_llm_request.ex`:
  - Replace `turn_index` derivation from `Conversation.Tracker`.
  - Build LLM context from `Jidoka.Messaging.list_session_messages/2` (plus existing working context/file context).
- Modify `lib/jidoka/agents/llm_orchestrator/actions/handle_llm_response.ex`:
  - Persist assistant response as message via `Jidoka.Messaging.append_session_message/4`.

### Phase 3 - Logging Model Cutover (Completed)
- Add a projection worker:
  - New file: `lib/jidoka/messaging/projections/conversation_graph_projection.ex`.
  - Subscribe to `jido.messaging.room.message_added` from the `Jidoka.Messaging` signal bus.
  - Write prompt/answer/tool entries to `Jidoka.Conversation.Logger`.
- Remove direct conversation logging signals:
  - Delete `lib/jidoka/agents/coordinator/actions/log_conversation_turn.ex`.
  - Remove references to `Jidoka.Signals.ConversationTurn` in:
    - `lib/jidoka/agents/llm_orchestrator/actions/handle_llm_request.ex`
    - `lib/jidoka/agents/llm_orchestrator/actions/handle_llm_response.ex`
    - `lib/jidoka/agents/llm_orchestrator/actions/handle_tool_call.ex`
    - `lib/jidoka/agents/llm_orchestrator/actions/handle_tool_result.ex`
- Keep `lib/jidoka/conversation/logger.ex` only as a projection sink.

### Phase 4 - Remove Legacy Runtime (In Progress)
- Delete legacy session conversation processes:
  - `lib/jidoka/conversation/tracker.ex`
  - `lib/jidoka/session/supervisor.ex`
  - `lib/jidoka/agents/session_manager.ex`
  - `lib/jidoka/session/state.ex`
  - `lib/jidoka/session/entry.ex`
  - `lib/jidoka/session/persistence.ex`
- Replace topic-level session routing (`lib/jidoka/pubsub.ex`) with messaging room/event subscriptions where conversation-specific.
- Update `lib/jidoka/client.ex` to use `Jidoka.Messaging` for conversation operations. (Completed)

### Phase 5 - API and Test Cleanup (In Progress)
- Remove dead `Signals` conversation constructors:
  - `lib/jidoka/signals/conversation_turn.ex`
  - relevant constructors in `lib/jidoka/signals.ex`
- Update tests:
  - Replace tracker tests with messaging runtime tests.
  - Replace signal-driven logging tests with projection-driven event tests.

## Data Mapping
- `session_id` -> room external binding key (`channel: :jidoka_session`, `instance_id: "jidoka-core"`, `external_id: session_id`)
- `conversation_iri` -> projection concern only (not runtime key)
- `turn_index` -> derived ordering from message stream (or projection metadata), not a runtime counter
- `prompt/answer/tool` signal types -> message roles + structured content/metadata

## Acceptance Criteria
- All user/assistant/tool interaction history is persisted in `Jidoka.Messaging`.
- No runtime dependency on `Conversation.Tracker`.
- No runtime dependency on `jido_coder.conversation.*` signal types.
- `Jidoka.Conversation.Logger` receives writes only from messaging projections.
- Chat request and response flow works with room/message APIs only.
