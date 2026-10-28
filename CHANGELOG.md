# Changelog — Pluto for Mac

All notable changes to the Mac port are documented here. SemVer applies.

## 0.1.0 — first Mac release

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
