# Contributing to Pluto for Mac

Thanks for jumping in! Here's how to get the repo building locally and add your changes.

## Setup

```bash
git clone https://github.com/chitransh-sr/pluto-mac.git
cd pluto-mac
./scripts/build.sh       # builds out/Pluto.app (no Xcode needed)
./scripts/install.sh     # installs to /Applications and launches
```

You only need the **macOS Command Line Tools** (`xcode-select --install`) — Swift 5.9+ ships with them.

## Architecture at a glance

```
┌──────────────┐     ┌──────────────┐     ┌───────────┐
│ OpenCode plugin │──POST /event/opencode──▶│ EventServer │──▶ SessionStore
│ Claude hooks    │──POST /event/claude─────▶(NWListener)│
│ Codex hooks     │──POST /event/codex──────▶            │
│ Gemini plugin   │──POST /event/gemini────▶            │
└──────────────┘                              │       ┌───▶ ProcessScanner (3s ps loop)
                                              │       │
                                              ▼       │
                                   SessionStore (single source of truth)
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    ▼                         ▼                         ▼
               PetRootView          TodoStore                   Prefs
                    │
            ┌───────┴────────┐
            ▼                ▼
       Notch body      Expanded panel
       (collapsed)     (sessions list, todos, settings)
```

- **`Sources/PlutoMac/*.swift`** — the entire app (single-module, no SPM deps).
- **`scripts/build.sh`** — `swiftc` build + Info.plist + icon assembly.
- **`scripts/install.sh`** — copies to `/Applications`, launches, restarts.
- **`Resources/PlutoIcon.png`** — source for `iconutil` (do **not** edit the generated `.icns`).
- **`Pluto.entitlements`** — ad-hoc entitlements for the unsigned build.

## Adding agent support

1. **Process scanner only** — add an entry to `AgentKind.swift`:
   ```swift
   case someAgent = "someagent"
   ```
   The scanner matches the executable basename or `node someagent` / `python -m someagent`.

2. **Full hooks** — add a method to `RelayInstaller.swift`:
   - `static func <agent>HooksInstalled() -> Bool`
   - `static func <agent>HookCommand(port:) -> String`
   - `func install<Agent>Hooks() / remove<Agent>Hooks()`
   - Wire the install call into `AppModel.firstLaunchSetup()`.

3. **Event types** — extend the `switch` in `SessionStore.applyEvent` with the new hook event names.

4. **Settings tab** — add a `Section` in `RelaysTab` with a `relayRow(...)`.

## Testing your changes

```bash
# Build and check for zero warnings:
./scripts/build.sh 2>&1 | grep -c warning  # should be 0

# Run unit tests:
swift test

# Install and verify:
./scripts/install.sh && curl -s http://127.0.0.1:7717/health | python3 -m json.tool
```

## Style

- 4-space indent.
- Prefer SwiftUI over raw AppKit unless you need panel control.
- Keep `SessionStore` as the single mutable state — views observe, they don't duplicate.
- One commit per logical change; reference issue numbers where relevant.
