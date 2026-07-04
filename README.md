# Pulsebus

> A small Elixir/OTP service that runs locally and accepts structured events from tools, scripts, editors, CLI commands, and local agents.

## Status

Early scaffold / experimental project.

Pulsebus is being built as a small, local-first Elixir/OTP project. The initial goal is to prove the core event bus shape before adding persistence, desktop notifications, a CLI wrapper, or any dashboard/TUI surface.

## Development

```bash
mix deps.get
mix format
mix test
```

## Local HTTP usage

Pulsebus starts a local HTTP server on `127.0.0.1:4040` by default.

```bash
curl localhost:4040/health
```

Emit an event:

```bash
curl -X POST localhost:4040/events \
  -H "content-type: application/json" \
  -d '{"topic":"repo.tests.failed","source":"repo","payload":{"cmd":"cargo test"}}'
```

Read recent events, newest first:

```bash
curl localhost:4040/events/recent
```

## CLI usage

Build the local CLI escript:

```bash
mix escript.build
```

Check the running service:

```bash
./pulse health
```

Emit an event:

```bash
./pulse emit repo.tests.failed \
  --source repo \
  --json '{"cmd":"cargo test","exit_code":101}'
```

Read recent events:

```bash
./pulse recent
```

The CLI defaults to `http://127.0.0.1:4040`. Override it with `PULSEBUS_URL`:

```bash
PULSEBUS_URL=http://127.0.0.1:4040 ./pulse health
```

## Why this exists

Pulsebus is a small side project for learning and using Erlang/Elixir in a place where using the BEAM runtime makes sense.

The BEAM is the virtual machine used by Erlang and Elixir. It was built for systems that need long-running processes, message passing, supervision, fault tolerance, and isolation. Those properties are useful for telecom systems, chat systems, control surfaces, background workers, and local coordination tools.

I keep getting the urge to add more Erlang/Elixir into larger projects, but I do not want to shoehorn BEAM into places where Rust, deterministic replay, or a simpler architecture is the better answer. Pulsebus has therefore been made to scratch that itch in a contained, useful way.

It is intended to be useful and educational without needing to become anything more. I am not trying to build Kafka, NATS, a distributed runtime, an agent framework, or a giant observability platform.

The goal is:

> Have local tools emit structured events for local subscribers to reliably react to.

## Summary

Pulsebus accepts local development events such as:

```text
codex.run.started
codex.run.finished
git.commit.created
repo.tests.failed
repo.tests.passed
model.downloaded
model.loaded
model.unloaded
blog.draft.updated
website.deploy.started
website.deploy.finished
```

Subscribers can then react to those events:

```text
notify me
write to local log
append to SQLite
send desktop notification
update tiny TUI
trigger safe local script
expose recent events over HTTP
```

BEAM doing BEAM: long-running, fault-tolerant, message-oriented coordination.

## Why an event bus fits BEAM

The event bus naturally wants the things Erlang and Elixir are good at.

| Need                               | Why BEAM fits                      |
| ---------------------------------- | ---------------------------------- |
| Long-running process               | OTP app/supervisor makes sense     |
| Many event producers               | Lightweight processes/channels     |
| Many subscribers                   | PubSub pattern                     |
| Crashes should not kill everything | Supervision trees                  |
| Live introspection                 | BEAM shell/observer-style thinking |
| Hot-ish runtime behaviour          | GenServers are natural             |
| Local coordination                 | No need for heavy infrastructure   |

## Project scope

Pulsebus starts with a deliberately small surface area:

```text
Elixir OTP app
GenServer event ingest
In-memory recent event buffer
Simple subscriber registration
Topic and prefix matching
Console/log subscriber
Optional local HTTP ingest
Optional CLI sender
```

Architecture:

```text
[pulse CLI / curl / scripts / tools]
                |
                v
        [Pulsebus HTTP ingest]
                |
                v
          [Event Router]
           /     |      \
          v      v       v
   [Log Sink] [Notify] [SQLite Sink]
```

The first working version should answer one question:

> Can local tools emit structured events, and can local subscribers react reliably?

## Non-goals

Pulsebus should stay small and local.

The initial project does **not** aim to provide:

```text
Distributed Erlang
Clustering
Cloud deployment
A Kafka/NATS replacement
A general agent runtime
Autonomy/control-plane semantics
A plugin marketplace
A large dashboard
Long-term analytics
Production observability guarantees
```

Those may be interesting ideas elsewhere. They are not the starting point here.

## Event model

Events are structured maps with a small required core:

```elixir
%{
  id: "evt_000001",
  topic: "repo.tests.failed",
  source: "repo",
  ts: "2026-07-01T09:30:00Z",
  payload: %{
    "command" => "cargo test",
    "exit_code" => 101
  }
}
```

Expected rules:

    * `id` is generated by Pulsebus.
    * `topic` is required.
    * `source` is required.
    * `ts` is generated by Pulsebus.
    * `payload` is optional.
    * `payload`, when present, must be a map.
    * Events should be append-only.
    * Subscribers should receive event copies, not mutate shared state.

Topic names should use dotted segments:

```text
repo.tests.failed
model.loaded
website.deploy.finished
codex.run.started
```

Subscriber filters may support exact topics or prefix wildcards:

```text
repo.tests.failed
repo.*
codex.run.*
model.*
website.deploy.*
```

## HTTP API surface

Pulsebus exposes a small local HTTP surface:

```text
POST /events
GET /events/recent
GET /health
```

Example event emission:

```bash
curl -X POST localhost:4040/events \
  -H "content-type: application/json" \
  -d '{"topic":"repo.tests.failed","source":"repo","payload":{"cmd":"cargo test"}}'
```

The HTTP implementation is intentionally thin. Event validation and routing stay inside the OTP event router.

## Planned CLI surface

A small CLI helper may eventually provide:

```bash
pulse emit repo.tests.failed --source repo --json '{"cmd":"cargo test"}'
pulse recent
pulse topics
```

The CLI is convenience, not the core system. The core is the OTP application and event router.

## Useful workflows

### Codex/OpenCode workflow logging

Wrap Codex/OpenCode runs manually:

```bash
pulse emit codex.run.started --source repo --json '{"wp":"WP38"}'
codex ...
pulse emit codex.run.finished --source repo --json '{"wp":"WP38","status":"ok"}'
```

### Repo test tracking

```bash
cargo test && \
pulse emit repo.tests.passed --source repo || \
pulse emit repo.tests.failed --source repo
```

### Local model lifecycle

```bash
pulse emit model.loaded --source desktop --json '{"model":"rusty","port":30100}'
```

### Website deploy events

```bash
pulse emit website.deploy.finished --source piestyx-site --json '{"target":"cloudflare"}'
```

## Development principles

Pulsebus should remain boring on purpose.

The project should favour:

    * clear OTP structure
    * small modules
    * simple event validation
    * obvious supervision boundaries
    * testable routing behaviour
    * local-only operation
    * minimal dependencies

The project should avoid:

    * premature clustering
    * broad abstractions
    * “platform” thinking
    * unclear plugin systems
    * hidden side effects
    * turning into another main project

## Initial implementation target

The first implementation should include:

```text
Mix project
OTP application
Event struct/schema module
GenServer event router
In-memory recent event buffer
Subscriber registration
Exact topic matching
Prefix wildcard matching
Console logger subscriber
Minimal tests
```

Initial behaviour to prove:

```text
emit_event validates and stores an event
recent_events returns newest-first bounded results
subscribers can register for exact topics
subscribers can register for prefix wildcards ending in .*
matching subscribers receive event messages
subscriber failure does not crash the router
```

Initial tests should cover:

```text
event validation
central ID generation
recent buffer bounds
exact topic matching
prefix topic matching
subscriber crash isolation
```

## Boundary

Pulsebus is a BEAM playground for local developer workflow events.
