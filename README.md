# Pluto for Mac 🪐

A Swift port of [Pluto for Windows](https://github.com/raktim-yoddha/pluto) for **macOS**,
built with **SwiftUI + AppKit** — no Xcode app required, no browser engine, no Electron.

A little bot with dotted eyes and a smile that lives at the top of your screen (or hugging
your MacBook's notch) and keeps an eye on every AI coding agent: **OpenCode** (first-class),
Claude Code, Codex, Gemini CLI, Cursor, Copilot CLI, Aider, Goose, Crush, Amp, Droid and
Qwen Code. It peeks out when one finishes or needs you, and keeps a daily To Do.

```
OpenCode plugin ──HTTP──▶┐
Claude Code hooks ─curl──┤
                         ├─ 127.0.0.1:<port> ▶ Session board ▶ notch bot ─▶ chime + banner
process scan (ps) ─3s────┘
```

## Install

Requires macOS 13.5+ (Apple Silicon; Intel works too). No other tooling to install.

```bash
git clone <this repo> pluto-mac && cd pluto-mac
./scripts/install.sh      # builds, installs to /Applications, launches
```

After the first launch, Pluto quietly installs its **OpenCode plugin** to
`~/.config/opencode/plugins/pluto.js` so it is OpenCode-ready immediately.
**Restart any open OpenCode sessions** (and the `opencode serve --service`) so OpenCode
loads the plugin, and your sessions start flowing in.

## Build

```bash
./scripts/build.sh        # → out/Pluto.app  (uses the macOS Command Line Tools only)
./scripts/install.sh      # → copies to /Applications and starts it
```

There is no SwiftPM/Xcode project on purpose: the toolchain installs of those are
flaky, and a plain `swiftc` build of ~15 files is instant and dependency-free.

## What it does

| You | Pluto |
| --- | --- |
| Nothing is happening | Sleeps in its notch at the top of the screen, just dotted eyes (floating: a little capsule) |
| Point at it | It pops, a little |
| An agent starts / finishes / needs you / fails | A short note hangs from the top edge for 3 s ("OpenCode is done · 3:41") with Pluto's chime |
| Click | The notch glides open into the list: **All agents** (sessions with state, project folder, snippet) and **To Do** |
| Click anywhere else | The list glides closed |
| Drag | Drop near the top edge to make a notch right there; anywhere else it floats |

### OpenCode compatibility (first-class)

*Installed automatically.* A global OpenCode plugin posts every session's
`created / idle / error / permission.asked / message.updated` events to Pluto over
`127.0.0.1:7717` (configurable in Settings). Because plugins are loaded by every
OpenCode session — CLI, `opencode serve`, or the desktop app — anything you do in
OpenCode shows up live: **working → needs you (approval) → done**, with the last
message as the session's caption. The plugin never throws; if Pluto is closed,
OpenCode runs as if it isn't there.

To re-install or remove it by hand: `Settings › Hooks & plugins`.

### Claude Code hooks

`Settings › Hooks & plugins › Install hooks` adds `UserPromptSubmit / Stop /
Notification` commands to `~/.claude/settings.json`, backing the original up as
`settings.json.before-pluto` the first time. Removing the hooks strips only Pluto's
entries.

### Everyone else

Codex, Gemini CLI, Cursor, Copilot CLI, Aider, Goose, Crush, Amp, Droid and Qwen Code
are found by a 3-second **process scan** (`ps`), the same trick Pluto's Windows
ProcessScanner uses — they show up as *working* rows while their CLIs run.

## To Do

A daily list in the To Do tab: add with Return, tap the circle to check (`✓` tasks sink
to the bottom), ⋯ menu to move/delete, and a History view with *Bring back unfinished*.
Everything saves immediately to `~/Library/Application Support/Pluto/todos.json`.
A new day starts at the hour you choose; the finished day moves to History
(keep 1 week … 1 year).

## Sound

Pluto's set: a soft tap when an agent starts, a chime when it's done, a knock when it
needs you (mapped to system sounds), or none, or your own WAV for a moment — drop it in
`~/Library/Application Support/Pluto/Sounds/<moment>.wav`, or use the picker in Settings.

## Settings

Notch or floating · Small / Medium / Large · hover pop · launch at login · watch list ·
port · hooks/plugins · per-moment sounds · To Do options.

## Privacy

Everything stays on your Mac. Sessions are kept in memory only: agent, project folder
name, and a few words of the current step. Prompts, file contents and command output are
never stored. No network access except Pluto's own feed on `127.0.0.1`.

## Differences from the Windows original

Same notch-bot idea, board and To Do — the things that depend on Windows APIs are not
included in 0.1: the compositor-drawn spring shoulders (SwiftUI springs animate the
shape instead), per-app window activation by PID for hook sessions, the update
channel, and the Hiveory link. The three-state board (working · needs you · done),
chimes, banners, To Do + History, launch-at-login and the settings cards are all here.

## License

MIT — adapted from [Pluto for Windows](https://github.com/raktim-yoddha/pluto) by
raktim-yoddha, MIT.
