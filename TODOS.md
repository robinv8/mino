# Technical TODOs

Items identified during architecture review (2026-03-15). Ordered by estimated ROI.

---

## 1. Migrate AppState from @ObservableObject to @Observable

**Why:** AppState has 12 `@Published` properties. Every single property change broadcasts `objectWillChange` to all subscribers, causing every view to re-evaluate — even if they only depend on one property. `@Observable` (macOS 14+) provides property-level granular subscriptions, eliminating unnecessary view updates.

**Current state:** `AppState` is ~1000 lines with `ObservableObject` + `@Published`. Streaming text updates (`content += delta`) fire `objectWillChange` ~30x/second, propagating to SidebarView, TaskPanel, etc. that don't need re-rendering.

**What to do:**
- Replace `class AppState: ObservableObject` → `@Observable class AppState`
- Remove all `@Published` property wrappers
- Replace `@StateObject` in MinoApp.swift with `@State`
- Replace `@EnvironmentObject` usage in views with `@Environment`
- Test: verify streaming doesn't cause sidebar flickering, TaskPanel unnecessary refreshes
- **Bonus fix:** The "silent update leak" (`updateMessage(silent: true)` still writes back to `conversations` triggering broadcast) becomes a non-issue with `@Observable`, since only views reading the specific changed property will update.

**Effort:** Medium (half-day). Mechanical changes, but need to test all views.
**Risk:** Low — `@Observable` is stable on macOS 14+, which is our minimum target.

---

## 2. Unified ACP / Claude Code Concurrency Model

**Why:** Two protocol backends use different concurrency patterns: `ACPClient` is an `actor`, while `ClaudeCodeClient` is a `@MainActor class` wrapping a `Task`. This creates inconsistency in error handling, cancellation, and message dispatch.

**Current state:**
- `ACPClient`: actor-isolated, uses `URLSessionWebSocketTask`, message dispatch via delegate callbacks
- `ClaudeCodeClient`: `@MainActor`, wraps `ClaudeCodeTransport` (spawns CLI process), dispatches via `onSessionUpdate` closure
- No shared protocol or abstraction between them

**What to do:**
- Define a shared `AgentTransport` protocol with `connect()`, `send()`, `disconnect()`, message stream
- Refactor both clients to conform to this protocol
- Unify error handling: both should produce the same error types for AppState to handle
- Consider: should both be actors? Or both `@MainActor`?

**Effort:** High (1-2 days). Touches core networking layer.
**Risk:** Medium — need to preserve existing ACP behavior while refactoring.
**Depends on:** Nothing. Can be done independently.

---

## 3. AgentTransport Protocol Abstraction

**Why:** Adding new protocol support (Matrix, MCP, etc.) currently means duplicating the entire client pattern. A shared protocol would make new backends plug-and-play.

**Current state:** `AppState` has separate code paths for ACP vs Claude Code in `connectAgent()`, `sendMessage()`, `disconnectAgent()`. Each new protocol doubles the branching.

**What to do:**
- Define `protocol AgentTransport: AnyObject` with lifecycle + messaging methods
- `ACPClient` and `ClaudeCodeClient` conform to it
- `AppState` holds `[String: any AgentTransport]` instead of separate `acpClients` / `claudeCodeClients`
- Reduces `switch agent.type` branching throughout AppState

**Effort:** Medium-High (1 day). Overlaps significantly with TODO #2.
**Risk:** Low — purely internal refactoring, no external-facing changes.
**Depends on:** Best done together with TODO #2.

---

## 4. Error Handling Infrastructure

**Why:** Errors from network, persistence, and JSONL parsing are silently swallowed with `try?`. Users see no feedback when things fail (e.g., save failure loses data silently, JSONL format change loses history silently).

**Current state:**
- `PersistenceService`: `try?` on all encode/write operations — write failure = silent data loss
- `ClaudeSessionLoader`: `try?` on JSON parse — format change = silent empty history
- `ACPClient`: errors logged to console but not surfaced to UI
- No unified error display mechanism

**What to do:**
- Add `@Published var lastError: AppError?` to AppState (or per-agent errors)
- Create `enum AppError` with cases for network, persistence, parsing, etc.
- Add a toast/banner component that shows errors with dismiss
- Replace critical `try?` with `do/catch` that sets `lastError`
- Keep `try?` only where failure is truly non-critical (e.g., optional resource extraction)

**Effort:** Medium (half-day for infrastructure, then incremental per-site fixes).
**Risk:** Low.
**Depends on:** Nothing. Can be done independently.

---

## 5. ClaudeSessionWatcher Polling Optimization

**Why:** `ClaudeSessionWatcher` polls every 2 seconds using a `Timer`. On macOS, `DispatchSource.makeFileSystemObjectSource` can provide event-driven file change notifications with zero CPU cost when idle.

**Current state:** 2-second timer fires 24/7 while an agent is active. Each tick calls `FileHandle.seekToEndOfFile()` + `readDataToEndOfFile()`. Negligible CPU but unnecessary wake-ups (bad for battery on laptops).

**What to do:**
- Replace `Timer` with `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:.write)`
- Keep a small debounce (100ms) to batch rapid writes
- Fallback to polling if dispatch source creation fails (e.g., too many file descriptors)
- Bonus: watch for new JSONL files appearing in the project directory (new sessions)

**Effort:** Low-Medium (2-3 hours).
**Risk:** Low — dispatch sources are well-tested on macOS.
**Depends on:** Nothing.
