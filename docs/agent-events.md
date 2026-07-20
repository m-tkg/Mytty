# Agent Event Protocol

Status: Implemented transport, provider adapters, hook helper, and installers.

Each mytty terminal surface receives three environment variables:

```text
MYTTY_EVENT_SOCKET
MYTTY_SURFACE_ID
MYTTY_EVENT_CAPABILITY
```

The capability authorizes event emission for that surface only. It does not
authorize terminal input, screen capture, or events for another surface. mytty
revokes it when the surface closes.

## Transport

Connect to `MYTTY_EVENT_SOCKET`, a user-only Unix stream socket with mode
`0600`. Send one UTF-8 JSON envelope, terminated by a newline, per connection.
The maximum request size is 64 KiB. Dates use ISO 8601.

```json
{
  "schemaVersion": 1,
  "capability": "value from MYTTY_EVENT_CAPABILITY",
  "event": {
    "schemaVersion": 1,
    "id": { "rawValue": "B9AA8B83-B42D-4C11-B838-36B84C73032A" },
    "runID": { "rawValue": "74C4B46D-9251-46AD-9200-61C97D98D43D" },
    "sessionID": "0190f6f3-2a50-7000-8000-000000000001",
    "surfaceID": { "rawValue": "value from MYTTY_SURFACE_ID" },
    "provider": "codex",
    "kind": "approval-requested",
    "occurredAt": "2026-07-16T07:00:00Z",
    "message": "Approve the dependency update."
  }
}
```

`id` must remain stable when a hook retries delivery. `runID` remains stable for
the lifetime of one agent run. `sessionID` is the provider's optional raw
session or conversation identifier and is shown only while that provider is
the foreground agent. Supported providers are `codex`, `claude-code`,
`opencode`, `antigravity`, and `cursor`.

Supported event kinds are:

```text
started
running
input-requested
approval-requested
succeeded
failed
disconnected
```

The server returns one JSON response and closes the connection:

```json
{ "ok": true, "inserted": true }
```

An idempotent retry returns `inserted: false`. Invalid JSON, authorization
failure, oversized input, and internal storage failure return `ok: false` with
a stable error code. Authorization responses never echo the capability.

## Lifecycle

Hooks should emit `started` before waiting or terminal events. Emit `running`
when work begins again after an input or approval request. Human-readable
terminal output must not be parsed to create these events.

mytty creates Attention items only for approval requests, input requests,
failures, disconnects, and successful work that ran for at least five minutes.
Acknowledged or otherwise resolved items remain visible for 24 hours.

Provider hook installation and lifecycle mappings are documented in
[`agent-integrations.md`](agent-integrations.md).
