---
name: event-mqtt
description: "Event-driven architecture standards — MQTT patterns (MQTTnet), Server-Sent Events (SSE), pub/sub design, topic hierarchies, QoS levels, message schemas, event sourcing, outbox pattern, and idempotency. Use this skill when implementing MQTT messaging, SSE streams, event handlers, pub/sub systems, or any asynchronous communication between services or between backend and frontend."
---

# Event-Driven Architecture Standards

This skill defines patterns for all event-driven communication across projects.

## Architecture Overview

```
[Frontend] <--SSE-- [API/Backend] <--MQTT-- [Devices/Services]
                         |
                    [PostgreSQL]
                    (event store)
```

- **MQTT (MQTTnet)**: Device-to-backend and backend-to-device communication
- **SSE (Server-Sent Events)**: Backend-to-frontend real-time updates
- **Database events**: Domain events persisted for audit and replay

## MQTT Patterns (MQTTnet 4.x)

### Topic Hierarchy Design
```
{tenant_id}/{domain}/{entity_type}/{entity_id}/{event_type}

Examples:
tenant_abc/devices/sensor/device_123/reading
tenant_abc/workflows/instance/inst_456/status_changed
tenant_abc/alerts/threshold/alert_789/triggered
```

### Rules
- Always prefix with `tenant_id` for multi-tenant isolation
- Use forward slashes `/` for hierarchy levels
- Use lowercase_snake_case for topic segments
- Max 5 levels deep — beyond that, put context in the payload
- Never include PII in topic names

### QoS Selection
| QoS | Guarantee | Use When |
|-----|-----------|----------|
| 0 | At most once (fire-and-forget) | Telemetry, high-frequency sensor data where occasional loss is OK |
| 1 | At least once | **Default** — commands, status updates, most business events |
| 2 | Exactly once | Financial transactions, compliance events (high overhead) |

### Retained Messages
- Use for **current state** topics (device online/offline, last known value)
- Clear retained messages when entity is deleted: publish empty payload with retain=true
- Never retain high-frequency data — only state snapshots

### Last Will and Testament (LWT)
```csharp
var options = new MqttClientOptionsBuilder()
    .WithWillTopic($"{tenantId}/devices/status/{deviceId}")
    .WithWillPayload("{\"status\":\"offline\"}")
    .WithWillRetain(true)
    .WithWillQualityOfServiceLevel(MqttQualityOfServiceLevel.AtLeastOnce)
    .Build();
```

### MQTTnet Client Pattern
```csharp
public class MqttService : BackgroundService
{
    private readonly IMqttClient _client;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        _client.ApplicationMessageReceivedAsync += HandleMessageAsync;

        await _client.ConnectAsync(BuildOptions(), ct);
        await _client.SubscribeAsync(new MqttTopicFilterBuilder()
            .WithTopic($"{_tenantId}/devices/#")
            .WithQualityOfServiceLevel(MqttQualityOfServiceLevel.AtLeastOnce)
            .Build(), ct);

        // Keep alive until cancelled
        await Task.Delay(Timeout.Infinite, ct);
    }

    private async Task HandleMessageAsync(MqttApplicationMessageReceivedEventArgs e)
    {
        var payload = Encoding.UTF8.GetString(e.ApplicationMessage.PayloadSegment);
        // Process message — use try/catch, log errors, don't throw
    }
}
```

### Security
- Always use TLS (port 8883) in production
- Per-tenant credentials or certificate-based auth
- ACL rules to restrict topic access by tenant/device
- Validate payload structure before processing

## Server-Sent Events (SSE)

### Why Not WebSocket?
SSE is simpler for server-to-client streaming. Use SSE when:
- Communication is one-directional (server → client)
- You need automatic reconnection (browser handles it)
- Proxies/load balancers need standard HTTP

### Backend Implementation
```csharp
[HttpGet("stream")]
[Authorize]
public async Task Stream(CancellationToken ct)
{
    Response.Headers["Content-Type"] = "text/event-stream";
    Response.Headers["Cache-Control"] = "no-cache";
    Response.Headers["X-Accel-Buffering"] = "no";  // Prevent proxy buffering

    var tenantId = User.FindFirst("tenant_id")?.Value;

    await foreach (var evt in _eventBus.Subscribe(tenantId, ct))
    {
        await Response.WriteAsync($"event: {evt.Type}\ndata: {evt.Json}\n\n", ct);
        await Response.Body.FlushAsync(ct);
    }
}
```

### Frontend Implementation
```typescript
// Use fetch + ReadableStream for authenticated SSE (EventSource doesn't support headers)
export function openEventStream(onEvent: (type: string, data: unknown) => void) {
  const controller = new AbortController()

  apiFetch('/api/events/stream', { signal: controller.signal })
    .then(async (response) => {
      const reader = response.body!.getReader()
      const decoder = new TextDecoder()
      // Parse SSE format...
    })

  return () => controller.abort()
}
```

### Vite Proxy (SSE Routes)
SSE routes need special proxy config — must appear BEFORE generic `/api` proxy:
```typescript
// vite.config.ts
proxy: {
  '/api/events/stream': {
    target: 'http://localhost:5000',
    changeOrigin: true,
    // Disable response buffering for SSE
    configure: (proxy) => {
      proxy.on('proxyRes', (res) => {
        res.headers['cache-control'] = 'no-cache'
      })
    },
  },
  '/api': { target: 'http://localhost:5000', changeOrigin: true },
}
```

### Reconnection Strategy
```typescript
const BACKOFF = { initial: 1000, max: 30000, multiplier: 2 }

function connectWithBackoff(attempt = 0) {
  const delay = Math.min(BACKOFF.initial * Math.pow(BACKOFF.multiplier, attempt), BACKOFF.max)
  // Connect, on error: setTimeout(() => connectWithBackoff(attempt + 1), delay)
  // On successful message: reset attempt to 0
}
```

## Event Type Parity

**CRITICAL**: Frontend and backend event type strings MUST stay in sync.

```csharp
// Backend: PlatformEventTypes.cs
public static class PlatformEventTypes
{
    public const string WorkflowCompleted = "workflow.completed";
    public const string WorkflowFailed = "workflow.failed";
    public const string HumanTaskCreated = "workflow.waiting_for_human";
}
```

```typescript
// Frontend: types/events.ts
export const EventTypes = {
  WORKFLOW_COMPLETED: 'workflow.completed',
  WORKFLOW_FAILED: 'workflow.failed',
  HUMAN_TASK_CREATED: 'workflow.waiting_for_human',
} as const
```

When adding a new event type: update BOTH files in the same change.

## Message Schema

### Standard Event Envelope
```json
{
  "id": "evt_abc123",
  "type": "workflow.completed",
  "tenantId": "tenant_xyz",
  "timestamp": "2025-01-15T10:30:00Z",
  "data": {
    "instanceId": "inst_456",
    "definitionId": "def_789",
    "status": "completed"
  }
}
```

### Rules
- Every event has `id`, `type`, `tenantId`, `timestamp`
- `id` must be globally unique (GUID or ULID)
- `type` uses dot-separated lowercase: `domain.entity.action`
- `data` contains event-specific payload
- No PII in event data unless encrypted

## Idempotency

### Consumer-Side
```csharp
// Track processed event IDs to handle at-least-once delivery
public async Task HandleEventAsync(DomainEvent evt)
{
    if (await _db.ProcessedEvents.AnyAsync(p => p.EventId == evt.Id))
        return;  // Already processed

    // Process event...

    _db.ProcessedEvents.Add(new ProcessedEvent { EventId = evt.Id });
    await _db.SaveChangesAsync();
}
```

### Outbox Pattern (For Reliable Publishing)
```csharp
// Write event to outbox table in same transaction as state change
await using var tx = await _db.Database.BeginTransactionAsync(ct);
_db.Goals.Add(newGoal);
_db.OutboxMessages.Add(new OutboxMessage
{
    Id = Guid.NewGuid(),
    Type = "goal.created",
    Payload = JsonSerializer.Serialize(new GoalCreatedEvent(newGoal.Id)),
    CreatedAt = DateTimeOffset.UtcNow,
});
await _db.SaveChangesAsync(ct);
await tx.CommitAsync(ct);

// Background service polls outbox and publishes, then marks as sent
```

## Anti-Patterns
- Putting business logic in event handlers — events should trigger, not decide
- Events without types or IDs — impossible to debug or replay
- Subscribing to wildcard topics (`#`) in production — use specific topics
- Blocking the MQTT message handler — process async, return quickly
- Missing reconnection logic — connections WILL drop
