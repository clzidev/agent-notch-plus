# Agent Notch

Your AI agents, living next to the MacBook notch.

While **Claude Code** or **Codex** is working, its mascot walks beside the notch — the Claude Code banner critter for Claude, the official Codex pet for Codex. Each agent has its own slot: the moment one finishes, its mascot becomes a green blob (even while the other keeps working). The green is a "finished since you last looked" notification — focusing your terminal clears it. Click to open a panel of your sessions, grouped by prompt, with every subagent tucked under a dropdown.

<p align="center"><img src="docs/indicator.gif" width="520" alt="Claude Code mascot and Codex pet walking beside the notch" /></p>

## The panel

One row per session, titled by the tool, led by **your** latest prompt — not the agents' chatter. Subagents (Codex's philosopher swarm, Claude's Task agents) fold under a `▸ N subagents` dropdown. Running rows show their mascot walking in place; finished rows get a green pixel checkmark. The tag on the right is the actual model that session runs.

<p align="center"><img src="docs/panel.png" width="600" alt="Session panel with subagent dropdowns" /></p>

## How it works

No hooks, no APIs, no accounts — it just polls the transcript files both CLIs already write, every 2 s:

- Claude Code: `~/.claude/projects/*/*.jsonl` (+ `<session>/subagents/agent-*.jsonl`)
- Codex: `~/.codex/sessions/**/*.jsonl`, grouped by `parent_thread_id`

A transcript modified in the last 20 s counts as *running*. Sessions idle over 6 h drop off. Activating a terminal app (Ghostty, Terminal, iTerm2, kitty, Warp, Alacritty) acknowledges finished agents and clears their green indicator.

The collapsed window is transparent and fully click-through except the tiny indicator zone, so it never blocks menu items or apps underneath. In fullscreen spaces the bar spans the whole top edge.

## Codex pet

The Codex animation uses the official Codex Pets spritesheets (in `pets/`). Switch pets with:

```sh
echo dewey > ~/.config/agent-notch/pet
```

Options: `codex`, `dewey`, `fireball`, `rocky`, `seedy`, `stacky`, `bsod`, `null-signal`. Takes effect within a couple of seconds, no restart needed. (Spritesheets © OpenAI, from their public pets CDN.)

## Build & run

```sh
swiftc -O main.swift -o AgentNotch
./AgentNotch &
```

- **Click** the indicator → open the panel. Click anywhere → close.
- To start at login: System Settings → General → Login Items → add `AgentNotch`.
- Requires macOS 12+ (built and tested on a notched MacBook; on notchless displays it centers on a virtual notch).
