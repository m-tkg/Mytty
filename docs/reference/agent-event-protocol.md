# Agent event protocol reference

The wire protocol coding-agent hooks use to report run state to Mytty.
Transport, provider adapters, the `mytty-agent-hook` helper, and the
per-provider installers are all implemented. Source:
`Sources/MyTTYCore/AgentEvent.swift`,
`Sources/MyTTYCore/AgentHookBridge.swift`. For which provider emits which
event kind, see [Agent providers](agent-providers.md).

## Environment variables

Each mytty terminal surface receives three environment variables:

```text
MYTTY_EVENT_SOCKET
MYTTY_SURFACE_ID
MYTTY_EVENT_CAPABILITY
```

`MYTTY_EVENT_CAPABILITY` authorizes event emission for that surface only.
It does not authorize terminal input, screen capture, or events for
another surface. Mytty revokes it when the surface closes.

## Transport

Connect to `MYTTY_EVENT_SOCKET`, a user-only Unix stream socket with mode
`0600`. Send one UTF-8 JSON envelope, terminated by a newline, per
connection. Maximum request size is 64 KiB. Dates are ISO 8601.

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

The server returns one JSON response and closes the connection:

```json
{ "ok": true, "inserted": true }
```

An idempotent retry returns `inserted: false`. Invalid JSON,
authorization failure, oversized input, and internal storage failure
return `ok: false` with a stable error code. Authorization responses
never echo the capability back.

## Envelope fields

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` (outer) | Int | Envelope schema version, currently `1` |
| `capability` | String | Must equal `MYTTY_EVENT_CAPABILITY` for this surface |
| `event.schemaVersion` | Int | Event schema version, currently `1` |
| `event.id` | `{rawValue: UUID}` | Must stay stable across a hook's retried delivery of the same event |
| `event.runID` | `{rawValue: UUID}` | Stable for the lifetime of one agent run (one prompt/turn) |
| `event.sessionID` | String? | Provider's own session/conversation identifier; shown only while that provider is the foreground agent |
| `event.surfaceID` | `{rawValue: <MYTTY_SURFACE_ID>}` | Must equal `MYTTY_SURFACE_ID` for this pane |
| `event.provider` | String | One of `codex`, `claude-code`, `opencode`, `antigravity`, `cursor` |
| `event.kind` | String | See event kinds below |
| `event.occurredAt` | String | ISO 8601 timestamp |
| `event.message` | String? | Optional human-readable detail, e.g. an approval prompt |

## Event kinds

`AgentEventKind` (wire values):

| Kind | Meaning |
| --- | --- |
| `started` | A new prompt or turn began |
| `running` | Work resumed after an input or approval request |
| `input-requested` | The agent needs free-form input from the user |
| `approval-requested` | The agent needs an approve/deny decision |
| `succeeded` | The run completed without error |
| `failed` | The run ended with an error |
| `disconnected` | The run ended because the provider process disconnected |

The reducer also derives an internal `idle` `AgentRunState` (not a wire
event kind) once a run has gone quiet after `succeeded`/`failed`/etc; see
`AgentRunState` in `Sources/MyTTYCore/AgentEvent.swift`.

## Lifecycle rules

Hooks should emit `started` before any waiting or terminal event. Emit
`running` when work begins again after an input or approval request.
Human-readable terminal output must never be parsed to synthesize these
events. Only structured hook payloads count.

## Attention item creation

Mytty creates Attention drawer items only for:

- approval requests
- input requests
- failures
- disconnects
- successful work that ran for at least five minutes

Acknowledged or otherwise resolved items remain visible in the drawer for
24 hours after resolution.

## Response codes

`AgentEventServerResponse` has three fields: `ok`, `inserted` (only set
on success), `error` (only set on failure, a stable code string).

| Response | Meaning |
| --- | --- |
| `{"ok": true, "inserted": true}` | Event accepted and newly recorded |
| `{"ok": true, "inserted": false}` | Idempotent retry of an already-recorded event (same `event.id`) |
| `{"ok": false, "error": "request-too-large"}` | Envelope exceeded the 64 KiB limit |
| `{"ok": false, "error": "unauthorized"}` | `capability` did not match this surface's `MYTTY_EVENT_CAPABILITY` |
| `{"ok": false, "error": "invalid-request"}` | Envelope could not be decoded as the expected JSON shape |
| `{"ok": false, "error": "internal-error"}` | Event storage failed on mytty's side |

## See also

- [Agent providers](agent-providers.md) covers file locations,
  per-provider hook-to-event mapping, and status bar/session-inspector
  sources.
- [mytty-ctl reference](mytty-ctl.md) documents the `list`/`wait`
  surface that reads the `AgentRunState` this protocol produces.
