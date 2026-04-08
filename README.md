# Project Highwind

An agentic coding orchestrator with a Final Fantasy-inspired airship bridge UI. Define a software project, hit "Set Course", and watch a crew of AI agents — rendered as FF-style pixel art sprites at their bridge stations — plan, build, test, and review your project in real time.

Built as an open source developer tool. Each agent has an XP and leveling system that grows across projects.

---

## How It Works

1. Open the **navigation console** and describe your project — name, goal, and optionally a tech stack
2. If you skip the tech stack, the orchestrator infers one from your goal and shows you a summary to confirm
3. Hit **"Set Course"** — the orchestrator decomposes your goal into a task graph and delegates to the crew
4. Watch the agents work in real time on the airship bridge; click any agent to tail their output on the CRT terminal panel

---

## The Crew

| Agent | Station | Role |
|---|---|---|
| Orchestrator | Captain's Chair | Parses goal, builds task graph, delegates work |
| Architect | Navigation/Helm | Designs file structure, tech choices, module boundaries |
| Coder | Engine Room | Writes implementation files |
| Tester | Radar/Comms | Writes and runs tests, reports failures |
| Reviewer | First Mate | Reads diffs, flags issues, suggests fixes |

Each agent has persistent XP and a level that grows across projects. Your Coder might be level 12 while your Tester is still level 4.

### Agent Levels

| Level | Title | Sprite |
|---|---|---|
| 1 | Recruit | Basic villager |
| 5 | Apprentice | Starter hero |
| 10 | Journeyman | Armored |
| 20 | Veteran | Full protagonist |
| 50 | Legend | Superboss, glowing effects |

---

## Tech Stack

- **Backend:** Elixir / Phoenix
- **Frontend:** Phoenix LiveView
- **Database:** PostgreSQL (via Ecto)
- **Background Jobs:** Oban
- **Real-time:** Phoenix PubSub
- **LLM:** Anthropic API (`claude-sonnet-4-20250514`) — backend only, never exposed to client

---

## Prerequisites

- Elixir 1.16+
- PostgreSQL
- An [Anthropic API key](https://console.anthropic.com/)

---

## Getting Started

```bash
# Clone the repo
git clone git@github.com:PFurtak/project-highwind.git
cd project-highwind

# Install dependencies
mix deps.get

# Set your Anthropic API key
export ANTHROPIC_API_KEY=your_key_here

# Set up the database
mix ecto.setup

# Start the server
mix phx.server
```

Then open [http://localhost:4000](http://localhost:4000).

---

## Architecture

The orchestrator is the only process that talks to the LLM for planning. Subagents receive narrow, structured instructions and report results back — no agent talks directly to another.

A shared **blackboard** (ETS-backed) acts as the project state store. Agents write artifacts (generated files, test results, review comments) to it; the orchestrator reads it to decide next steps.

Heavy LLM calls run as **Oban jobs** — persistent, retryable, and crash-safe. GenServers own agent identity and PubSub broadcasting. LLM API calls are wrapped with a circuit breaker to handle rate limits gracefully.

Default pipeline: `plan → architect → code → test → review → done`

The orchestrator can loop (e.g. failed tests re-queue the coder with error context).

---

## Contributing

Users bring their own Anthropic API key. License TBD (MIT or Apache 2.0).

Issues and PRs welcome.
