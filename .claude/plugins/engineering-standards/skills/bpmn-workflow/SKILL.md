---
name: bpmn-workflow
description: "BPMN 2.0 workflow engine standards — process modeling, gateway patterns (exclusive/parallel/inclusive), human tasks, timer events, error handling, compensation, state machines, and workflow persistence. Use this skill when implementing workflow engine features, designing process definitions, building gateway logic, implementing human task flows, or working with the workflow builder."
---

# BPMN 2.0 & Workflow Engine Standards

This skill defines patterns for workflow engine implementation following BPMN 2.0 standards.

## BPMN 2.0 Core Concepts

### Element Types
| BPMN Element | Our Implementation | Shape |
|---|---|---|
| Start Event | Trigger node (Manual, Cron, Webhook) | Circle |
| End Event | End node | Circle (thick border) |
| Task | Action node (HTTP, DB, Email, etc.) | Rounded rectangle |
| User Task | Human Task node | Rounded rectangle with person icon |
| Exclusive Gateway | Decision node — ONE path taken | Diamond |
| Parallel Gateway | Split & Wait — ALL paths, no conditions | Diamond |
| Inclusive Gateway | Match node — MATCHING paths taken | Diamond |
| Timer Event | Delay node | Circle with clock |
| Sub-Process | For Each (loop) node | Rounded rectangle with scope zone |

### Gateway Semantics (CRITICAL)

#### Exclusive Gateway (Decision — XOR)
- Evaluates conditions on outgoing edges **in order**
- Takes the **first** matching path
- Must have a default path (fallback)
- **Conditions live on edges**, not the gateway node
- Gateway ConfigPanel shows: question label + outgoing path summary
- User clicks an edge to open the ConditionBuilder

#### Parallel Gateway (Split & Wait — AND)
- **Splits**: ALL outgoing paths fire unconditionally
- **Joins**: Waits for ALL incoming paths before continuing
- **NO conditions** — ever. ConditionBuilder must NEVER appear for parallel edges
- Use for concurrent operations (e.g., "send email AND update inventory AND notify Slack")

#### Inclusive Gateway (Match — OR)
- Evaluates conditions on all outgoing edges
- Takes ALL matching paths (not just the first)
- Must have a default path for when nothing matches
- Join waits only for the paths that were actually taken

### Anti-Patterns
- Conditions on parallel gateway edges (BPMN violation)
- Missing default paths on exclusive/inclusive gateways (creates dead-end workflows)
- Deeply nested gateways (>3 levels) — refactor into sub-processes
- Gateway nodes trying to hold business logic — gateways ROUTE, they don't COMPUTE

## Workflow Engine Architecture

### Instance Lifecycle
```
Created → Running → [Suspended | WaitingForHuman | Completed | Failed]
                         ↓                ↓
                      Running          Running (on resume)
```

### State Machine Rules
```csharp
public enum WorkflowStatus
{
    Pending,            // Created but not started
    Running,            // Currently executing
    Suspended,          // Waiting on timer/retry
    WaitingForHuman,    // Human task pending
    Completed,          // Successfully finished
    Failed              // Unrecoverable error
}
```

Valid transitions:
- `Pending → Running` (trigger fires)
- `Running → Completed` (reached end node)
- `Running → Failed` (unrecoverable error)
- `Running → Suspended` (delay, retry backoff)
- `Running → WaitingForHuman` (human task created)
- `Suspended → Running` (timer/retry fires)
- `WaitingForHuman → Running` (human approves/rejects)

### Execution Model
```csharp
public async Task ExecuteInstanceAsync(WorkflowInstance instance, CancellationToken ct)
{
    instance.Status = WorkflowStatus.Running;
    instance.ErrorCode = null;      // Clear stale errors from retry
    instance.ErrorMessage = null;

    while (instance.CurrentNodeId != null)
    {
        var node = graph.GetNode(instance.CurrentNodeId);
        var executor = _registry.Resolve(node.Type);

        var result = await executor.ExecuteAsync(context);

        // Handle result: advance to next node, suspend, complete, or fail
    }
}
```

## Node System

### Node Contract
Every node type has:
1. **Descriptor** (backend): Declares params, default outputs, category
2. **Executor** (backend): Implements `ExecuteAsync`, produces output DataBag
3. **Definition** (frontend): Mirrors descriptor — params, outputs, display info

### Output Contract
```csharp
// Descriptor declares what the executor produces
public OutputFieldDef[] DefaultOutputs => new[]
{
    new OutputFieldDef("order_id", "Order ID", OutputType.String),
    new OutputFieldDef("total", "Total Amount", OutputType.Number),
};

// Executor MUST set exactly these keys
output.Set("order_id", orderId);
output.Set("total", totalAmount);
```

**CRITICAL**: `DefaultOutputs` keys must EXACTLY match executor `DataBag` keys AND frontend `nodeDefinitions.ts` keys. All three locations must stay in sync.

### Expression Evaluation
- Nodes reference upstream outputs via `{{ nodes.node_1.field_name }}`
- Expression evaluator resolves at runtime from `WorkflowVariables`
- After JSON round-trip (suspend/resume), values are `JsonElement` — evaluator handles both CLR types and JsonElement

### Test Mode
```csharp
public async Task ExecuteAsync(NodeContext ctx)
{
    if (ctx.IsTest)
    {
        ctx.Output.Set("result", "[TEST] Simulated output");
        return;
    }
    // Real execution...
}
```

Side-effecting executors MUST check `ctx.IsTest`. Read-only executors don't need guards.

## Human Tasks

### Flow
1. Workflow reaches Human Task node → status becomes `WaitingForHuman`
2. Task appears in user's task list (SSE notification sent)
3. User reviews data, makes decision (approve/reject/custom)
4. `POST /api/workflows/{id}/resume` with decision payload
5. Engine resumes, stores payload under `vars["__resume"]` (namespaced)
6. Downstream nodes access via `{{ __resume.decision }}`

### Resume Payload Safety
**CRITICAL**: Never merge resume payloads into top-level workflow variables. Namespace under `__resume` to prevent variable collision with downstream node configs.

## Timer & Scheduling

### Delay Node
```csharp
// Suspend instance with ResumeAfter timestamp
instance.Status = WorkflowStatus.Suspended;
instance.ResumeAfter = DateTimeOffset.UtcNow.Add(delay);
```

### Cron Triggers
- Use Cronos library for cron expression evaluation
- Scheduler polls every 30s for due triggers
- Track `_lastFired` per definition to prevent double-firing

### Retry with Backoff
```csharp
instance.Status = WorkflowStatus.Suspended;
instance.ErrorCode = "TRANSIENT_FAILURE";  // MUST set for scheduler to distinguish retry from delay
instance.ResumeAfter = DateTimeOffset.UtcNow.AddSeconds(Math.Pow(2, instance.RetryCount));
```

## Error Handling

### Transient vs Permanent Errors
| Type | Example | Action |
|------|---------|--------|
| Transient | HTTP 503, timeout, connection refused | Retry with backoff (max 3 attempts) |
| Permanent | 404, validation failure, business rule | Fail immediately with clear error message |
| Compensation | Partial completion of multi-step | Run compensation handlers |

### Error Propagation
```csharp
try
{
    await executor.ExecuteAsync(context);
}
catch (TransientException ex)
{
    instance.RetryCount++;
    if (instance.RetryCount >= MaxRetries)
    {
        instance.Status = WorkflowStatus.Failed;
        instance.ErrorMessage = $"Max retries exceeded: {ex.Message}";
    }
    else
    {
        instance.Status = WorkflowStatus.Suspended;
        instance.ErrorCode = "TRANSIENT_FAILURE";
        instance.ResumeAfter = CalculateBackoff(instance.RetryCount);
    }
}
catch (Exception ex)
{
    instance.Status = WorkflowStatus.Failed;
    instance.ErrorMessage = ex.Message;
}
```

## Graph Persistence

- Workflow definitions stored as JSON graph in database
- Graph deserialization MUST use `JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower)` to match global config
- Node positions, connections, and configs all serialized
- On load: advance `nextNodeId` past all existing IDs to prevent collisions

## UX Principles (The Non-Technical User Test)

> "Can a non-technical user who uses basic office tools daily but has never written a formula, build this workflow in under 5 minutes without help?"

- **Zero syntax** — no brackets, dots, or template expressions visible to users
- **Human-readable labels** — "Split & Wait" not "Parallel Split"
- **Click-to-configure** — data pills for expressions, not text input
- **Conditions on edges** — not in gateway config panels
- **Visual scope zones** — For Each loops show a tinted region
