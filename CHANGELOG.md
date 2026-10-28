# Changelog — Pluto for Mac

All notable changes to the Mac port are documented here. SemVer applies.

## 0.2.0 — premium UI & production polish

* **Notch** shrunk to fit eyes + face only (72–96 px vs 100–140 px), eyes enlarged (4.2 px / 20 % of height) and brought closer together
* **Expanded panel**: 20 pt continuous corners, 24 pt depth shadow, `white.10` stroke — HUD aesthetic instead of generic border
* **Spinner**: `TimelineView`-driven `circle.dashed.circle` with continuous rotation, no leaked `@State` timers
* **Caption**: now dual-line — state + project + live duration on top, snippet below; 1 Hz `tick` timer keeps the duration and age labels updating while a session is working
* **Scan filtering**: GUI helper processes (Cursor) and sessions with unresolved cwd are dropped; scan rows for agents with a live SSE event session are hidden
* **Header**: fixed 48 px height, no `.ignoresSafeArea` bleed, bold "Pluto" title, "reconnecting…" label
* **Footer**: accuracy fix — shows "N active · N tracked · N events" instead of misleading "N sessions"; green LED with glow
* **SessionRowView**: hover fill (`white.08`) + avatar glow; `checkmark.shield` for done, `exclamationmark.shield` for needs-you; full-row click target
* **Agent activation**: click → `NSRunningApplication` via PID, falling back to ProcessScanner's last PID, then bundle ID
* **Double-tap** on the notch to expand; **reconnect button** in the empty state
* **To Do tab**: `Divider()` → custom `white.06` separators, gradient progress header, styled add-field
* **App icon**: Pluto-the-planet icon (reddish-brown with Sputnik Planitia heart) packaged as `Pluto.icns`
* App build version 0.2, bundle ID `com.chitransh-sr.pluto-mac`

* The notch bot (SwiftUI + AppKit): black notch shape with dotted eyes and smile,
  blinks and breathes, pops on hover, never takes focus while small
* Placement: notch hugging the top edge (drop it anywhere along the edge to make a
  notch there) or floating capsule; Small / Medium / Large
* Board: All agents list with working / needs-you / done / failed states,
  project folder, snippet, durations, click to bring the app forward
* OpenCode compatibility: global plugin (~/.config/opencode/plugins/pluto.js) that
  streams session.created / idle / error / permission.asked / message.updated to
  Pluto on 127.0.0.1:7717 — installed automatically on first launch
* Claude Code hooks installer (UserPromptSubmit / Stop / Notification) with
  `*.before-pluto` backups, plus a tolerant remover that strips only its entries
* Process scanner: 3 s `ps` loop finding every watched agent CLI
  (Claude Code, OpenCode, Codex, Gemini CLI, Cursor, Copilot CLI, Aider, Goose,
  Crush, Amp, Droid, Qwen Code)
* Banners + chimes: soft tap / chime / knock / thud per moment, or none, or a
  custom WAV per moment
* Daily To Do with History: rollover at your chosen start hour, bring unfinished
  back, saved right away to ~/Library/Application Support/Pluto/todos.json
* Settings: macOS-System-Settings-style tabs (General / Agents / Hooks & plugins /
  Sound / To Do / About), launch at login
* Menu bar item (🪐): open the list, settings, feed state, quit
