# CLAUDE.md — Project Highwind

## Project Overview

A Phoenix LiveView application that functions as an agentic coding orchestrator with a
Final Fantasy-inspired airship bridge UI. Users define a software project (tech stack + goal),
kick it off, and watch a crew of AI agents — rendered as FF-style pixel art sprites at their
bridge stations — plan, build, test, and review the project in real time.

This is intended as an open source developer tool. Gamification (agent XP and leveling) is
a core feature, not an afterthought.

---

## Tech Stack

- **Backend:** Elixir / Phoenix
- **Frontend:** Phoenix LiveView (no separate JS framework)
- **Database:** PostgreSQL (via Ecto)
- **Background Jobs:** Oban
- **Real-time:** Phoenix PubSub + Channels
- **HTTP Client:** Req (for Anthropic API calls)
- **LLM:** Anthropic API (claude-sonnet-4-20250514) — backend only, never exposed to client

---

## Architecture Patterns

### Supervisor Tree (OTP)
All agent GenServers live under `AgentSupervisor`. Each agent is an isolated fault domain —
a crashed coder agent restarts without affecting the orchestrator or other agents.

### Orchestrator / Worker
The `OrchestratorServer` is the only process that talks to the LLM for planning and task
decomposition. Subagents receive narrow, scoped instructions and report results back.
No agent talks directly to another agent.

### Blackboard Pattern
A shared ETS table (or Postgres-backed store) acts as the project blackboard. Agents write
artifacts (generated files, test results, review comments) to the blackboard. The orchestrator
reads the blackboard to decide next steps. Agents are fully decoupled from each other.

### Event-Driven / PubSub
Agents broadcast state changes and terminal output as PubSub events. LiveView subscribes
and reacts. Adding a new agent means adding a subscriber — no rewiring of existing code.

### Pipeline
Default task flow: `plan → architect → code → test → review → done`.
The orchestrator drives this pipeline and can branch or loop (e.g. failed tests re-queue
the coder with error context).

### Command Pattern
Agent instructions are structured Elixir structs (e.g. `%CodingTask{files: [...], instructions: "..."}`),
not raw strings. Makes handoffs serializable and agent behavior testable.

### Hybrid GenServer + Oban
- GenServers own agent identity, sprite state, and PubSub broadcasting (always-alive, stateful)
- Oban workers handle heavy LLM calls (persistent, retryable, survives restarts)
- Flow: GenServer enqueues Oban job → worker calls LLM → broadcasts result via PubSub →
  GenServer receives, updates state → LiveView rerenders

### Circuit Breaker
LLM API calls are wrapped with a circuit breaker (Fuse library) to prevent cascading
failures from rate limits or timeouts.

---

## Agent Roster

| Agent | GenServer | Station | Role |
|---|---|---|---|
| Orchestrator | `OrchestratorServer` | Captain's Chair | Parses goal, builds task graph, delegates |
| Architect | `ArchitectAgent` | Navigation/Helm | Designs file structure, tech choices, module boundaries |
| Coder | `CoderAgent` | Engine Room | Writes implementation files |
| Tester | `TesterAgent` | Radar/Comms | Writes and runs tests, reports failures |
| Reviewer | `ReviewerAgent` | First Mate | Reads diffs, flags issues, suggests fixes |

---

## Key Modules

| Module | Purpose |
|---|---|
| `MissionControlLive` | Main LiveView — canvas, sprites, terminal panel |
| `OrchestratorServer` | GenServer — task graph, LLM planning calls, delegation |
| `AgentServer` (×4) | GenServer per agent — status, output buffer, PubSub broadcast |
| `AgentSupervisor` | Supervisor tree for all agent GenServers |
| `LLMClient` | Thin Req wrapper for Anthropic API (streaming-capable) |
| `ProjectConfig` | Ecto schema — stack, goal, status, agent XP/level persistence |
| `Blackboard` | Shared state store — artifacts, intermediate results |

---

## UI / UX

### Scene
A fixed overhead pixel art **airship bridge interior** (inspired by FF7 Highwind /
FFX Fahrenheit). Not a draggable canvas — a static scene with absolutely positioned
sprites over a background image. No drag-and-drop needed.

```
<div class="scene">
  <img class="background" src="bridge.png" />
  <div class="agent" style="top: 120px; left: 340px" phx-click="select_agent">
    <img class="sprite" src="coder-idle.gif" />
  </div>
</div>
```

### Sprite Animation
CSS sprite sheets with `steps()` animation. Agent status atom maps directly to CSS class:
- `:idle` → standing frame
- `:working` → walk/active animation
- `:error` → red flash

### Terminal Output Panel
A **CRT TV / ship communication screen** at the front of the bridge. Clicking an agent
subscribes the panel to `agent:{name}` PubSub topic. Output streams line by line into a
`<pre>` block with:
- Scanline overlay (CSS pseudo-element, repeating linear-gradient)
- Phosphor glow (green/amber text-shadow bloom)
- Screen flicker on mount (CSS keyframe)
- Auto-scroll via JS hook

### Project Config
Styled as the **navigation console**. LiveView form with `phx-change`. Fields:

| Field | Type | Required | Notes |
|---|---|---|---|
| Project name | text input | yes | used as the working directory name |
| Goal / description | textarea | yes | what the project should do |
| Tech stack | tag/token input | no | if empty, orchestrator infers it |
| Language version hints | text input | no | e.g. "Node 20", "Python 3.12" |

Submit button label: **"Set Course"** (never "Kick Off" or "Submit").

#### Tech Stack Inference Flow

If the user leaves tech stack empty, the orchestrator performs a **stack inference call**
before building the task graph. This is a dedicated, lightweight LLM call — not part of
planning — whose only job is to return a structured stack recommendation.

```
goal description
      │
      ▼
OrchestratorServer.infer_stack/1   ← single LLM call, <500 tokens
      │
      ▼
%StackInference{
  languages: ["TypeScript"],
  frameworks: ["Next.js", "Prisma"],
  databases: ["PostgreSQL"],
  rationale: "..."          ← shown to user before proceeding
}
      │
      ▼
MissionControlLive renders "Inferred stack" confirmation banner
User can accept or edit before pipeline starts
```

The inferred stack is displayed as a read-only summary with an **"Edit stack"** escape hatch
that re-opens the form fields. The orchestrator does not begin planning until the user
explicitly confirms (clicks "Set Course" a second time, or the banner auto-accepts after
10 seconds with a visible countdown).

#### `%ProjectConfig{}` Schema Fields

```elixir
%ProjectConfig{
  name: string,           # required
  goal: string,           # required
  tech_stack: [string],   # [] means "not provided — inferred"
  stack_inferred: boolean,
  stack_rationale: string | nil,
  language_hints: string | nil,
  status: :draft | :confirming_stack | :running | :done | :error
}
```

`status: :confirming_stack` is the intermediate state while the user reviews an inferred
stack. The orchestrator must not proceed past this state without an explicit `:confirmed`
transition.

On final submit → sends `%ProjectConfig{}` to `OrchestratorServer` → LLM decomposes into
task graph → pipeline begins.

---

## Gamification

### Agent Leveling
Each agent has persistent XP and level stored in Postgres. Thresholds unlock new sprites.

| Level | Title | Sprite |
|---|---|---|
| 1 | Recruit | Basic villager |
| 5 | Apprentice | Starter hero |
| 10 | Journeyman | Armored |
| 20 | Veteran | Full protagonist |
| 50 | Legend | Superboss, glowing effects |

### XP Awards
- Task completed → base XP
- Tests pass first try → bonus XP
- Reviewer requests zero changes → bonus XP
- Task completed under estimated complexity → bonus XP

XP is role-based, not user-based. Your Coder is level 12, your Tester is level 4.
Encourages using all agents and creates attachment to individual crew members.

---

## PubSub Topics

| Topic | Publisher | Subscriber |
|---|---|---|
| `agent:orchestrator` | OrchestratorServer | MissionControlLive |
| `agent:architect` | ArchitectAgent | MissionControlLive |
| `agent:coder` | CoderAgent | MissionControlLive |
| `agent:tester` | TesterAgent | MissionControlLive |
| `agent:reviewer` | ReviewerAgent | MissionControlLive |
| `orchestrator:updates` | All AgentServers | OrchestratorServer |

---

## LLM Integration Notes

- API calls are **backend only** — the Anthropic API key is never exposed to the client
- Use `System.fetch_env!("ANTHROPIC_API_KEY")` — never hardcode keys
- Use streaming responses via Req so output pipes through PubSub line-by-line
- Model: `claude-sonnet-4-20250514`
- Each agent has its own system prompt defining its narrow role
- The orchestrator system prompt handles planning and task decomposition only

---

## Project Structure

The app module is `Highwind` and web module is `HighwindWeb`. Follow standard Phoenix
conventions: business logic lives under `lib/highwind/`, the web layer under
`lib/highwind_web/`. Never put business logic in the web layer and never put web
concerns in the business layer.

```
highwind/
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   ├── runtime.exs          # runtime secrets (ANTHROPIC_API_KEY, DATABASE_URL, etc.)
│   └── test.exs
│
├── lib/
│   ├── highwind/            # Business logic — no web, no Phoenix HTTP concerns
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   │
│   │   ├── agents/          # Context module for agent data (XP, level, status)
│   │   │   ├── agents.ex        # public API — all DB access for agents goes here
│   │   │   └── agent.ex         # Ecto schema
│   │   │
│   │   ├── projects/        # Context module for project configs
│   │   │   ├── projects.ex
│   │   │   └── project_config.ex  # Ecto schema
│   │   │
│   │   ├── orchestration/   # OTP process tree
│   │   │   ├── agent_supervisor.ex
│   │   │   ├── orchestrator_server.ex
│   │   │   ├── architect_agent.ex
│   │   │   ├── coder_agent.ex
│   │   │   ├── tester_agent.ex
│   │   │   └── reviewer_agent.ex
│   │   │
│   │   ├── workers/         # Oban workers (one file per job type)
│   │   │   ├── orchestrate_worker.ex
│   │   │   ├── architect_worker.ex
│   │   │   ├── coder_worker.ex
│   │   │   ├── tester_worker.ex
│   │   │   └── reviewer_worker.ex
│   │   │
│   │   ├── blackboard.ex    # ETS-backed shared state — only module that touches ETS
│   │   └── llm_client.ex    # Req wrapper for Anthropic API — only module that calls Req
│   │
│   └── highwind_web/        # Web layer — Phoenix router, LiveViews, components
│       ├── endpoint.ex
│       ├── router.ex
│       ├── telemetry.ex
│       │
│       ├── live/            # LiveView modules + collocated templates
│       │   ├── mission_control_live.ex
│       │   └── mission_control_live.html.heex   # collocated template
│       │
│       └── components/      # Reusable function components
│           ├── core_components.ex   # Phoenix-generated core components
│           ├── layouts.ex
│           └── agent_sprite.ex      # project-specific components
│
├── assets/
│   ├── css/
│   │   └── app.css
│   └── js/
│       ├── app.js
│       └── hooks/           # LiveView JS hooks (one file per hook)
│           └── terminal_scroll.js
│
├── priv/
│   ├── repo/
│   │   └── migrations/
│   └── static/
│       └── images/          # Bridge background, sprite sheets
│
├── test/
│   ├── highwind/            # Mirror lib/highwind/ structure
│   │   ├── agents/
│   │   ├── projects/
│   │   ├── orchestration/
│   │   ├── workers/
│   │   ├── blackboard_test.exs
│   │   └── llm_client_test.exs
│   ├── highwind_web/        # Mirror lib/highwind_web/ structure
│   │   └── live/
│   │       └── mission_control_live_test.exs
│   └── support/
│       ├── conn_case.ex
│       ├── data_case.ex
│       └── fixtures/        # Factory helpers for test data
│
└── mix.exs
```

### Structure Rules

- **One context per domain** — `Highwind.Agents` owns all agent DB access; `Highwind.Projects`
  owns all project DB access. Cross-context calls go through the public context API,
  never via direct schema queries.
- **Collocated templates** — every LiveView `.ex` file has a `.html.heex` file alongside it
  in the same directory. Do not use `render/1` with inline `~H` sigils in LiveView modules
  except for trivial one-liners.
- **One Oban worker per job type** — each worker module handles exactly one kind of LLM task.
  Workers live in `lib/highwind/workers/`, not inside agent or context modules.
- **JS hooks in `assets/js/hooks/`** — one file per hook, all imported and registered in
  `app.js`. Never inline hook logic in templates.
- **Migrations in `priv/repo/migrations/`** — never modify existing migrations; always add
  new ones.
- **Test support fixtures** — test data factories live in `test/support/fixtures/`; use
  `ExMachina` or plain builder functions, never seed data directly in test files.

---

## Build Order

1. Static scene with hardcoded sprite positions and CSS animations
2. Agent GenServers + PubSub broadcasting mock output
3. Terminal panel wiring (click → subscribe → stream)
4. `AgentSupervisor` + `OrchestratorServer` skeleton
5. `LLMClient` with streaming support
6. Orchestrator LLM call → task graph → delegation
7. Real subagent LLM calls (file write, run tests, etc.)
8. Project config form → "Set Course" kick-off flow
9. Blackboard implementation
10. XP / leveling system + sprite unlocks

---

## Development Process (Claude Code Instructions)

These rules apply when developing Project Highwind itself. They are not inherited by
the orchestrator agents when users run their own projects.

### TDD — Strict Red/Green/Refactor
1. **Red** — write a failing test that defines the desired behavior before any implementation
2. **Green** — write the minimum code needed to make the test pass, nothing more
3. **Refactor** — clean up the implementation without changing behavior, tests must still pass

Never write implementation code without a failing test first. If you are tempted to skip
this because something feels trivial, write the test anyway.

### Quality Gates (run after every task)
All four of these must pass before a task is considered complete:

- **Security audit** — check for hardcoded secrets, exposed API keys, PubSub messages
  containing unsanitized LLM output, and any API calls made outside `LLMClient`
- **Linting / code style** — run `mix format` and `mix credo` and resolve all warnings
- **Test suite** — run `mix test` and ensure the full suite passes with no failures
- **Reviewer sign-off** — treat every completed unit of work as a PR; review the diff
  before moving to the next task

### Code Conventions
- No direct DB queries outside of context modules — all DB access goes through a context
- No direct ETS access outside of the `Blackboard` module
- No raw `Req` calls outside of `LLMClient`
- Agent instructions are always structs, never raw strings
- API keys loaded via `System.fetch_env!` only — never interpolated into strings or logged
- No business logic in LiveView modules — keep them as thin display and event layers
- `Ecto.Multi` is required for all operations that combine multiple DB writes

### Dependency Rules
- No new dependencies added without a justification comment in the commit message
- Format: `Add <library> — <one sentence reason>`
- Example: `Add Fuse — circuit breaker for LLM API calls to prevent cascade failures`

### Changelog
- Every PR must include a `CHANGELOG.md` entry under an `Unreleased` header
- Format follows Keep a Changelog (Added / Changed / Fixed / Removed)

---

## Open Source Notes

- License: TBD (MIT or Apache 2.0 recommended)
- Users bring their own Anthropic API key
- Sprite assets must be original or openly licensed (not ripped from FF games)
- Good sources: itch.io, OpenGameArt.org, or custom commission
- Sprite sheets preferred over GIFs for CSS animation state control

---

## Conventions

- Agent status is always an atom: `:idle | :working | :done | :error`
- Agent instructions are always structs, never raw strings
- All LLM calls go through `LLMClient` — never call Req directly from an agent
- Blackboard reads/writes go through the `Blackboard` module — never access ETS directly
- PubSub topic names follow the pattern `agent:{role_name}`
