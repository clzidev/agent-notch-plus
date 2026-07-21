# Agent Notch Plus

Your AI agents, living next to the MacBook notch.

> Fork of [realfishsam/agent-notch](https://github.com/realfishsam/agent-notch) — all credit for the original concept, design and implementation goes to its author. This fork adds a global keyboard shortcut, hover-to-open, and a settings panel with custom animated-GIF mascots. See [What this fork adds](#what-this-fork-adds).

While **Claude Code** or **Codex** is working, its mascot walks beside the notch — the Claude Code banner critter for Claude, the official Codex pet for Codex. Each agent has its own slot: the moment one finishes, its mascot becomes a green blob (even while the other keeps working). The green is a "finished since you last looked" notification — focusing your terminal clears it. Click to open a panel of your sessions, grouped by prompt, with every subagent tucked under a dropdown.

<p align="center"><img src="docs/indicator.gif" width="520" alt="Claude Code mascot and Codex pet walking beside the notch" /></p>

## The panel

One row per session, titled by the tool, led by **your** latest prompt — not the agents' chatter. Subagents (Codex's philosopher swarm, Claude's Task agents) fold under a `▸ N subagents` dropdown. Running rows show their mascot walking in place; finished rows get a green pixel checkmark. The tag on the right is the actual model that session runs.

<p align="center"><img src="docs/panel-demo.gif" width="600" alt="Session panel with walking mascots and subagent dropdowns" /></p>

## How it works

No hooks, no APIs, no accounts. Liveness detection follows [open-vibe-island](https://github.com/Octane0411/open-vibe-island)'s model — *a session is a running agent process in a terminal* — polled every 3 s:

- `ps` finds `claude`/`codex` processes attached to a TTY (headless/background sessions are ignored)
- `lsof` maps each process to the transcript it holds open (Codex), or to its working directory (Claude Code, which doesn't keep the transcript fd open)
- transcripts provide the metadata: prompts, snippets, models, subagents
  - Claude Code: `~/.claude/projects/*/*.jsonl` (+ `<session>/subagents/agent-*.jsonl`)
  - Codex: `~/.codex/sessions/**/*.jsonl`, grouped by `parent_thread_id`

Within a live session, *busy vs idle* is a hybrid: process alive + transcript written in the last 30 s = busy (mascot walks); alive but quiet = idle (nothing in the notch, dimmed row in the panel); process gone for 2 polls = done (green blob). Sessions idle over 6 h drop off the panel. Activating a terminal app (Ghostty, Terminal, iTerm2, kitty, Warp, Alacritty) acknowledges finished agents and clears their green indicator.

### Known limitation: the ~30 s afterglow

Busy/idle is inferred from transcript write times, and transcript writes are bursty — so the mascot keeps walking for up to ~33 s (30 s window + 3 s poll) after a turn actually ends, and conversely a turn's quiet stretches are smoothed over. No process-level proxy (network, CPU, child processes) can fully fix this: only the agent knows when its turn ends. The precise fix would be agent hooks (`UserPromptSubmit`/`Stop` writing a state file, as open-vibe-island does), deliberately skipped here to keep the zero-config, no-hooks design. If the afterglow bothers you, that's the upgrade path.

The collapsed window is transparent and fully click-through except the tiny indicator zone, so it never blocks menu items or apps underneath. In fullscreen spaces the bar spans the whole top edge.

## What this fork adds

- **Global hotkey — ⌃⌥N (Control + Option + N)** toggles the panel, no mouse needed. Registered via Carbon `RegisterEventHotKey`, so it needs no Accessibility/Input-Monitoring permission.
- **Hover to open** — rest the cursor on the indicator (~0.35 s) and the panel opens; it closes when the mouse leaves it. Click/hotkey opens stay put until dismissed.
- **Settings panel** — right-click the indicator (or the open panel) → *Configuración…*:
  - pick the Codex pet from a dropdown (no more editing config files by hand)
  - set a **custom animated GIF** per agent that replaces its mascot in the notch and in the panel rows — transparent-background GIFs look best on the black bar
- **Hover zoom** — while the panel is open, hovering it grows it by a configurable percentage (default 25%); the font size stays the same but snippets unfold into several lines, so you read *more* text. It shrinks back when the mouse leaves.
- **Notch terminal** (configurable hotkey, default ⌃⌥Space) — a real terminal ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)) that unrolls from the notch like a curtain and rolls back up when hidden, with its shells kept running. It is part of the notch: it cannot be moved, and resizing from any edge grows it symmetrically, always centered under the notch. **⌘D** splits it into up to 3 side-by-side panes. Minimal matrix-style prompt — just `dir branch ❯` with a blinking green block cursor (your `~/.zshrc` is still sourced, colors intact). Run `claude` or `codex` in one and answer their confirmations right from the notch. `exit` closes a pane, ✕ force-closes everything even if a shell hangs.
- **Animated emoji mascots — no API, no account** — a scrollable gallery of 60 [Noto Animated Emoji](https://googlefonts.github.io/noto-emoji-animation/) (small transparent-background GIFs served by Google's public CDN). Search by name (EN/ES), click one and it instantly replaces the Claude or Codex mascot; one click restores the original. Fetching these emoji is the app's only network access.
- **Sounds** (optional, off by default) — a chime when an agent finishes (Glass) and when it goes quiet awaiting your input (Ping). At most once per activity episode.
- **Bilingual UI** — English/Spanish, selectable in settings (defaults to the system language).
- Config lives in `~/.config/agent-notch/` (`pet`, `claude-gif`, `codex-gif`, `lang`, `zoom`, `term-hotkey`, `sound-done`, `sound-attention`; downloaded emoji land in `gifs/`) and is re-read every 3 s, so changes apply live.
- The Codex pet spritesheets are now resolved relative to the binary (with the original hardcoded path as fallback), so the app works from any clone location.

## Codex pet

The Codex animation uses the official Codex Pets spritesheets (in `pets/`). Switch pets with:

```sh
echo dewey > ~/.config/agent-notch/pet
```

Options: `codex`, `dewey`, `fireball`, `rocky`, `seedy`, `stacky`, `bsod`, `null-signal`. Takes effect within a couple of seconds, no restart needed. (Spritesheets © OpenAI, from their public pets CDN.)

## Build & run

```sh
swift build -c release
cp .build/release/AgentNotchPlus AgentNotch
./AgentNotch &
```

(The first build fetches [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) via Swift Package Manager.)

- **Click** the indicator → open the panel. Click anywhere → close.
- To start at login: System Settings → General → Login Items → add `AgentNotch`.
- Requires macOS 12+ (built and tested on a notched MacBook; on notchless displays it centers on a virtual notch).

## Credits

- **[realfishsam](https://github.com/realfishsam)** — author of the original [agent-notch](https://github.com/realfishsam/agent-notch), which is all of the core of this project (MIT license, kept intact in [LICENSE](LICENSE)).
- **[open-vibe-island](https://github.com/Octane0411/open-vibe-island)** — the process-discovery liveness model the original follows.
- **OpenAI** — the Codex Pets spritesheets in `pets/` (© OpenAI, from their public pets CDN).
- **[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)** by Miguel de Icaza — the terminal emulator embedded in the notch terminal (MIT).
- **Google** — the [Noto Animated Emoji](https://googlefonts.github.io/noto-emoji-animation/) used as optional mascots (Noto Emoji, OFL/Apache licensing by Google Fonts).
- The walking Claude mascot is drawn from the Claude Code launch-banner block characters.
